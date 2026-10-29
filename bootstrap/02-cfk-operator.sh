#!/usr/bin/env bash
# bootstrap/02-cfk-operator.sh — install Confluent for Kubernetes operator.
#
# Usage: bash bootstrap/02-cfk-operator.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1) CONTEXT=$KUBECTL_CONTEXT_REGION1; NAMESPACE=$NAMESPACE_REGION1 ;;
  east2) CONTEXT=$KUBECTL_CONTEXT_REGION2; NAMESPACE=$NAMESPACE_REGION2 ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

CFK_NAMESPACE=confluent

echo "[$(date +%H:%M:%S)] Installing Confluent for Kubernetes operator on ${CONTEXT}"
echo "  Operator namespace: ${CFK_NAMESPACE}  (watches cluster-wide via namespaced=false)"
echo "  Workload namespace: ${NAMESPACE}"

# ─── Install CFK operator ───
helm repo add confluentinc https://packages.confluent.io/helm >/dev/null 2>&1 || true
helm repo update confluentinc >/dev/null

kubectl --context "$CONTEXT" create namespace "$CFK_NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

helm --kube-context "$CONTEXT" upgrade --install confluent-operator \
  confluentinc/confluent-for-kubernetes \
  --version "$CFK_VERSION" \
  -n "$CFK_NAMESPACE" \
  --set namespaced=false \
  --wait --timeout 5m

# ─── Create workload namespace ───
kubectl --context "$CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

echo "✓ CFK operator installed in $CFK_NAMESPACE (version $CFK_VERSION)"
kubectl --context "$CONTEXT" -n "$CFK_NAMESPACE" get pods
