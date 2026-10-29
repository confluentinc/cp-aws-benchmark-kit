#!/usr/bin/env bash
# Topology A — Route53 sync. UPSERT alias A records for:
#   bootstrap.<domain>  → kafka-listener-clusterlink-bootstrap-lb NLB
#   broker{0..N-1}.<domain> → kafka-listener-clusterlink-{i}-lb NLB
#
# Idempotent — safe to re-run.
#
# Usage: bash client-path/topology-a-nlb-per-pod/route53-sync.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1)
    CONTEXT=$KUBECTL_CONTEXT_REGION1
    NAMESPACE=$NAMESPACE_REGION1
    ZONE_ID=$ROUTE53_ZONE_ID_REGION1
    DOMAIN=$DOMAIN_REGION1
    NLB_HOSTED_ZONE=$NLB_HOSTED_ZONE_REGION1
    ;;
  east2)
    CONTEXT=$KUBECTL_CONTEXT_REGION2
    NAMESPACE=$NAMESPACE_REGION2
    ZONE_ID=$ROUTE53_ZONE_ID_REGION2
    DOMAIN=$DOMAIN_REGION2
    NLB_HOSTED_ZONE=$NLB_HOSTED_ZONE_REGION2
    ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

[[ -z "$ZONE_ID" ]] && { echo "ERROR: ROUTE53_ZONE_ID_* missing in .env"; exit 1; }

echo "[$(date +%H:%M:%S)] Topology A Route53 sync for ${REGION_KEY}"
echo "  zone:    ${DOMAIN} (${ZONE_ID})"

BROKER_COUNT_LIVE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get sts kafka -o jsonpath='{.spec.replicas}')
echo "  brokers: ${BROKER_COUNT_LIVE}"

declare -A NAME_TO_NLB
BOOTSTRAP_NLB=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" \
  get svc kafka-listener-clusterlink-bootstrap-lb \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NAME_TO_NLB["bootstrap"]="$BOOTSTRAP_NLB"

for i in $(seq 0 $((BROKER_COUNT_LIVE - 1))); do
  nlb=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    get svc "kafka-listener-clusterlink-${i}-lb" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  [[ -n "$nlb" ]] && NAME_TO_NLB["broker${i}"]="$nlb"
done

echo "  resolved $(echo "${!NAME_TO_NLB[@]}" | wc -w | tr -d ' ') NLB hostnames"

PAYLOAD=/tmp/r53-topology-a-${REGION_KEY}.json
echo '{"Comment": "cp-benchmark-kit Topology A sync", "Changes": [' > "$PAYLOAD"
first=1
for name in "${!NAME_TO_NLB[@]}"; do
  [[ $first -eq 0 ]] && echo "," >> "$PAYLOAD"
  cat >> "$PAYLOAD" <<EOF
{"Action":"UPSERT","ResourceRecordSet":{"Name":"${name}.${DOMAIN}","Type":"A","AliasTarget":{"HostedZoneId":"${NLB_HOSTED_ZONE}","DNSName":"${NAME_TO_NLB[$name]}","EvaluateTargetHealth":true}}}
EOF
  first=0
done
echo "]}" >> "$PAYLOAD"

echo "[$(date +%H:%M:%S)] Applying Route53 change batch..."
change_id=$(aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --change-batch "file://$PAYLOAD" --profile "$AWS_PROFILE" \
  --query 'ChangeInfo.Id' --output text)

for i in 1 2 3 4 5 6; do
  status=$(aws route53 get-change --id "$change_id" --profile "$AWS_PROFILE" --query 'ChangeInfo.Status' --output text)
  [[ "$status" == "INSYNC" ]] && { echo "  ✓ INSYNC"; break; }
  sleep 10
done

echo "✓ Topology A DNS synced for $REGION_KEY"
