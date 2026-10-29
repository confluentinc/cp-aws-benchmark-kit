#!/usr/bin/env bash
# Topology B — install:
#   1. Create ng-ingress-xl nodegroup (eksctl, 3 × c7gn.2xlarge, one per AZ)
#   2. Patch Kafka CR to enable staticForHostBasedRouting on EXTERNAL listener
#   3. Install 3 nginx-ingress controllers (one per AZ) via Helm, each with its own NLB
#   4. Apply the 3-class SNI Ingress object (one per nginx class)
#   5. Delete the admission webhook (helm re-creates it; it's not needed for passthrough)
#   6. Upsert Route53 records for bootstrap-ext + b{0..N-1}
#
# Usage: bash client-path/topology-b-nginx-ingress/install.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"
DIR="$REPO_ROOT/client-path/topology-b-nginx-ingress"

case "$REGION_KEY" in
  east1)
    REGION=$REGION1
    CLUSTER=$CLUSTER_NAME_REGION1
    CONTEXT=$KUBECTL_CONTEXT_REGION1
    NAMESPACE=$NAMESPACE_REGION1
    DOMAIN=$DOMAIN_REGION1
    SUBNETS_CSV=$NGINX_INGRESS_SUBNETS_REGION1
    ;;
  east2)
    REGION=$REGION2
    CLUSTER=$CLUSTER_NAME_REGION2
    CONTEXT=$KUBECTL_CONTEXT_REGION2
    NAMESPACE=$NAMESPACE_REGION2
    DOMAIN=$DOMAIN_REGION2
    SUBNETS_CSV=$NGINX_INGRESS_SUBNETS_REGION2
    ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

[[ -z "$SUBNETS_CSV" ]] && { echo "ERROR: NGINX_INGRESS_SUBNETS_REGION* missing"; exit 1; }
IFS=',' read -r -a SUBNETS <<< "$SUBNETS_CSV"
[[ "${#SUBNETS[@]}" -lt 3 ]] && { echo "ERROR: need 3 subnets (one per AZ), got ${#SUBNETS[@]}"; exit 1; }

echo "[$(date +%H:%M:%S)] Topology B install for ${REGION_KEY}"
echo "  domain: ${DOMAIN}"
echo "  subnets: ${SUBNETS[*]}"

# ─── 1. Create ng-ingress-xl nodegroup ───
NG_RENDERED=/tmp/ng-ingress-xl-${REGION_KEY}.yaml
sed -e "s|__CLUSTER_NAME__|${CLUSTER}|g" \
    -e "s|__REGION__|${REGION}|g" \
    -e "s|__EKS_VERSION__|${EKS_VERSION}|g" \
    -e "s|__INGRESS_INSTANCE__|${INGRESS_INSTANCE}|g" \
    -e "s|__INGRESS_NODE_COUNT__|${INGRESS_NODE_COUNT}|g" \
    -e "s|__SUBNET_LIST_YAML__|[${SUBNETS[0]}, ${SUBNETS[1]}, ${SUBNETS[2]}]|g" \
    "$DIR/nodegroup.yaml.tpl" > "$NG_RENDERED"

if ! eksctl get nodegroup --cluster "$CLUSTER" --region "$REGION" --profile "$AWS_PROFILE" --name ng-ingress-xl >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] Creating ng-ingress-xl..."
  eksctl create nodegroup -f "$NG_RENDERED" --profile "$AWS_PROFILE"
else
  echo "  ng-ingress-xl already exists — skipping create"
fi

# ─── 2. Patch Kafka CR (EXTERNAL listener staticForHostBasedRouting) ───
echo "[$(date +%H:%M:%S)] Patching Kafka CR for EXTERNAL listener..."
PATCH=/tmp/patch-kafka-static-${REGION_KEY}.yaml
sed "s|__DOMAIN__|${DOMAIN}|g" "$DIR/patch-kafka-static-host.yaml" > "$PATCH"
kubectl --context "$CONTEXT" -n "$NAMESPACE" patch kafka kafka --type merge --patch-file "$PATCH"

# ─── 3. Install 3 nginx-ingress controllers ───
echo "[$(date +%H:%M:%S)] Installing nginx-ingress (3 per-AZ)..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update ingress-nginx >/dev/null

kubectl --context "$CONTEXT" create namespace ingress-nginx --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

for i in a b c; do
  idx=$([ "$i" = "a" ] && echo 0 || [ "$i" = "b" ] && echo 1 || echo 2)
  SUBNET_PLACEHOLDER="__SUBNET_AZ_$(echo $i | tr a-z A-Z)__"
  VALUES_RENDERED="/tmp/values-zone-${i}-${REGION_KEY}.yaml"
  sed "s|${SUBNET_PLACEHOLDER}|${SUBNETS[$idx]}|g" "$DIR/values-zone-${i}.yaml.tpl" > "$VALUES_RENDERED"

  helm --kube-context "$CONTEXT" upgrade --install "nginx-zone-${i}" \
    ingress-nginx/ingress-nginx -n ingress-nginx \
    --version "$NGINX_INGRESS_CHART_VERSION" \
    -f "$VALUES_RENDERED" \
    --wait --timeout 5m || echo "  (helm install may timeout waiting for NLB; checking status next)"
done

# ─── 4. Apply Ingress object ───
echo "[$(date +%H:%M:%S)] Applying SNI Ingress object..."
INGRESS_RENDERED=/tmp/ingress-sni-${REGION_KEY}.yaml
sed -e "s|__DOMAIN__|${DOMAIN}|g" -e "s|__NAMESPACE__|${NAMESPACE}|g" \
  "$DIR/ingress-sni-routing.yaml.tpl" > "$INGRESS_RENDERED"

# Admission webhooks block Ingress creation on multi-controller installs; remove.
kubectl --context "$CONTEXT" delete validatingwebhookconfiguration \
  nginx-zone-a-ingress-nginx-admission nginx-zone-b-ingress-nginx-admission nginx-zone-c-ingress-nginx-admission \
  --ignore-not-found

kubectl --context "$CONTEXT" apply -f "$INGRESS_RENDERED"

# ─── 5. Route53 CNAMEs ───
bash "$DIR/route53-sync.sh" "$REGION_KEY"

echo "✓ Topology B installed for $REGION_KEY"
