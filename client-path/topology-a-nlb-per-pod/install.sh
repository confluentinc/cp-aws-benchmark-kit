#!/usr/bin/env bash
# Topology A — install (idempotent).
#
# 1. envsubst the Kustomize patch with the region's domain + subnets from .env
# 2. kubectl apply the Kafka CR with the custom clusterlink listener added
# 3. Wait for 16 NLBs (bootstrap + 15 brokers) to come up
# 4. Upsert Route53 CNAMEs pointing bootstrap/broker{N} → NLB DNS names
#
# Usage: bash client-path/topology-a-nlb-per-pod/install.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1)
    CONTEXT=$KUBECTL_CONTEXT_REGION1
    NAMESPACE=$NAMESPACE_REGION1
    DOMAIN=$DOMAIN_REGION1
    SUBNETS=$NGINX_INGRESS_SUBNETS_REGION1
    ;;
  east2)
    CONTEXT=$KUBECTL_CONTEXT_REGION2
    NAMESPACE=$NAMESPACE_REGION2
    DOMAIN=$DOMAIN_REGION2
    SUBNETS=$NGINX_INGRESS_SUBNETS_REGION2
    ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

[[ -z "$SUBNETS" ]] && { echo "ERROR: NGINX_INGRESS_SUBNETS_REGION* missing in .env — run 'make tf-output-to-env'"; exit 1; }

PATCH_FILE="$REPO_ROOT/client-path/topology-a-nlb-per-pod/patch-kafka-clusterlink.yaml"
RENDERED="/tmp/patch-kafka-clusterlink-${REGION_KEY}.yaml"

echo "[$(date +%H:%M:%S)] Topology A install for ${REGION_KEY}"
echo "  domain:  ${DOMAIN}"
echo "  subnets: ${SUBNETS}"

sed -e "s|__DOMAIN__|${DOMAIN}|g" -e "s|__SUBNETS__|${SUBNETS}|g" "$PATCH_FILE" > "$RENDERED"

# Apply the patch directly (strategic merge against the existing Kafka CR)
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch kafka kafka --type merge \
  --patch-file "$RENDERED"

echo "[$(date +%H:%M:%S)] Waiting for 16 NLBs to come up (bootstrap + ${BROKER_COUNT} brokers)..."
for i in $(seq 1 60); do
  ready=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get svc -l app=kafka \
    -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' \
    2>/dev/null | grep -c '.elb.' || true)
  echo "  attempt $i: $ready/$((BROKER_COUNT + 1)) NLBs ready"
  [[ "$ready" -ge "$((BROKER_COUNT + 1))" ]] && break
  sleep 15
done

bash "$REPO_ROOT/client-path/topology-a-nlb-per-pod/route53-sync.sh" "$REGION_KEY"
echo "✓ Topology A installed for $REGION_KEY"
