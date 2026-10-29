#!/usr/bin/env bash
# OTel + Tempo + Jaeger install.
#
# Usage: bash observability/otel-stack/install.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"
DIR="$REPO_ROOT/observability/otel-stack"

case "$REGION_KEY" in
  east1) CONTEXT=$KUBECTL_CONTEXT_REGION1 ;;
  east2) CONTEXT=$KUBECTL_CONTEXT_REGION2 ;;
  *) echo "Unknown: $REGION_KEY"; exit 1 ;;
esac

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

echo "[$(date +%H:%M:%S)] Installing OTel stack on ${CONTEXT}"

# ─── Tempo ───
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update grafana >/dev/null
helm --kube-context "$CONTEXT" upgrade --install tempo grafana/tempo \
  -n "$MONITORING_NAMESPACE" -f "$DIR/tempo-values.yaml" --wait --timeout 5m

# ─── Jaeger (all-in-one) ───
kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" apply -f "$DIR/jaeger-allinone.yaml"

# ─── OTel Collector ───
# Template out the collector configmap + deployment with monitoring namespace
RENDERED_CM=/tmp/otel-cm-${REGION_KEY}.yaml
RENDERED_DEPLOY=/tmp/otel-deploy-${REGION_KEY}.yaml
export NAMESPACE="$MONITORING_NAMESPACE"
export MONITORING_NAMESPACE OTEL_COLLECTOR_IMAGE
envsubst '${NAMESPACE} ${MONITORING_NAMESPACE}' < "$DIR/otel-collector-configmap.yaml.tpl" > "$RENDERED_CM"
envsubst '${NAMESPACE} ${MONITORING_NAMESPACE} ${OTEL_COLLECTOR_IMAGE}' < "$DIR/otel-collector-deployment.yaml.tpl" > "$RENDERED_DEPLOY"

kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" apply -f "$RENDERED_CM"
kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" apply -f "$RENDERED_DEPLOY"

echo "✓ OTel stack installed for $REGION_KEY"
