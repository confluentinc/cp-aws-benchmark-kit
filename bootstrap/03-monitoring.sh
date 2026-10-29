#!/usr/bin/env bash
# bootstrap/03-monitoring.sh — install kube-prometheus-stack + OTel + Tempo + Jaeger.
#
# This installs the FULL observability stack:
#   - kube-prometheus-stack (Prometheus + Grafana + Node Exporter + ...)
#   - 8 custom Grafana dashboards (via sidecar-provisioned ConfigMaps)
#   - OTel Collector (OTLP gRPC :4317 / HTTP :4318)
#   - Tempo (trace backend)
#   - Jaeger all-in-one (parallel trace backend for comparison)
#   - OMB JMX exporter ConfigMap
#
# To install only Prometheus + Grafana (no tracing stack), set OTEL_SKIP=1.
#
# Usage: bash bootstrap/03-monitoring.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1) CONTEXT=$KUBECTL_CONTEXT_REGION1; NAMESPACE=$NAMESPACE_REGION1 ;;
  east2) CONTEXT=$KUBECTL_CONTEXT_REGION2; NAMESPACE=$NAMESPACE_REGION2 ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

echo "[$(date +%H:%M:%S)] Installing observability stack on ${CONTEXT} (namespace: ${MONITORING_NAMESPACE})"

# ─── Namespace ───
kubectl --context "$CONTEXT" create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

# ─── kube-prometheus-stack ───
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null

# Render parameterized values file (replaces __MONITORING_NAMESPACE__ with actual ns)
RENDERED_VALUES=/tmp/kube-prom-values-${REGION_KEY}.yaml
sed "s|__MONITORING_NAMESPACE__|${MONITORING_NAMESPACE}|g" \
  "$REPO_ROOT/observability/values-kube-prometheus-stack.yaml" > "$RENDERED_VALUES"

helm --kube-context "$CONTEXT" upgrade --install kps \
  prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  -n "$MONITORING_NAMESPACE" \
  -f "$RENDERED_VALUES" \
  --wait --timeout 10m

# ─── Grafana dashboards (sidecar-provisioned ConfigMaps) ───
echo "[$(date +%H:%M:%S)] Applying Grafana dashboard ConfigMaps"
if [[ -f "$REPO_ROOT/observability/grafana-dashboards-configmaps.yaml" ]]; then
  kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" apply -f \
    "$REPO_ROOT/observability/grafana-dashboards-configmaps.yaml"
fi

# ─── OMB JMX exporter ConfigMap (in CP namespace, used by benchmark workers) ───
if [[ -f "$REPO_ROOT/observability/jmx-exporter/omb-client-config.yaml" ]]; then
  echo "[$(date +%H:%M:%S)] Applying OMB JMX exporter ConfigMap in ${NAMESPACE}"
  envsubst < "$REPO_ROOT/observability/jmx-exporter/omb-client-config.yaml" | \
    kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f -
fi

# ─── OTel + Tempo + Jaeger (optional) ───
if [[ "${OTEL_SKIP:-0}" == "1" ]]; then
  echo "OTel/Tempo/Jaeger install skipped (OTEL_SKIP=1)"
else
  echo "[$(date +%H:%M:%S)] Installing OTel + Tempo + Jaeger"
  bash "$REPO_ROOT/observability/otel-stack/install.sh" "$REGION_KEY"
fi

# ─── Access info ───
GRAFANA_PWD=$(kubectl --context "$CONTEXT" -n "$MONITORING_NAMESPACE" \
  get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d 2>/dev/null || echo "n/a")

echo
echo "✓ Observability stack installed on $REGION_KEY"
echo
echo "Grafana access:"
echo "  kubectl --context $CONTEXT -n $MONITORING_NAMESPACE port-forward svc/kps-grafana 3000:80"
echo "  URL:      http://localhost:3000"
echo "  user:     admin"
echo "  password: $GRAFANA_PWD"
echo
echo "Prometheus access:"
echo "  kubectl --context $CONTEXT -n $MONITORING_NAMESPACE port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090"
