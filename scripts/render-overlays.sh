#!/usr/bin/env bash
# render-overlays.sh — in-place sed to update Kustomize overlay namespaces + DNS
# values from .env. Idempotent — safe to re-run.
#
# Updates:
#   confluent/overlays/east1/kustomization.yaml  — namespace + cflt-east1 DNS refs
#   confluent/overlays/east2/kustomization.yaml  — same for east2
#   cluster-link/overlays/east1/kustomization.yaml  — namespace + source bootstrap endpoint
#   cluster-link/overlays/east2/kustomization.yaml  — same
#
# Called automatically by `make deploy-cp-east{1,2}` so users only edit .env.
#
# Usage: bash scripts/render-overlays.sh <east1|east2|both>

set -euo pipefail
REGION_KEY="${1:-both}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

render_region() {
  local key=$1 ns_old=$2 ns_new=$3 domain_new=$4 domain_peer=$5

  echo "[$key] rewriting overlays: namespace=$ns_new, domain=$domain_new"

  # Confluent overlay — namespace + in-cluster DNS refs (kafka.<ns>.svc.cluster.local etc.)
  local f="$REPO_ROOT/confluent/overlays/$key/kustomization.yaml"
  if [[ -f "$f" ]]; then
    sed -i.bak \
      -e "s|^namespace: .*|namespace: $ns_new|" \
      -e "s|$ns_old\.svc\.cluster\.local|$ns_new.svc.cluster.local|g" \
      "$f"
    rm "${f}.bak"
  fi

  # Cluster-link overlay — namespace + source bootstrap (points at OTHER region's domain)
  local cl="$REPO_ROOT/cluster-link/overlays/$key/kustomization.yaml"
  if [[ -f "$cl" ]]; then
    sed -i.bak \
      -e "s|^namespace: .*|namespace: $ns_new|" \
      -e "s|bootstrap\.cl\.cp\.east[12]\.example\.internal|bootstrap.$domain_peer|g" \
      -e "s|cflt-east[12]-|cflt-$key-|g" \
      "$cl"
    rm "${cl}.bak"
  fi
}

if [[ "$REGION_KEY" == "east1" || "$REGION_KEY" == "both" ]]; then
  render_region east1 cflt-east1 "$NAMESPACE_REGION1" "$DOMAIN_REGION1" "$DOMAIN_REGION2"
fi
if [[ "$REGION_KEY" == "east2" || "$REGION_KEY" == "both" ]]; then
  render_region east2 cflt-east2 "$NAMESPACE_REGION2" "$DOMAIN_REGION2" "$DOMAIN_REGION1"
fi

echo "✓ Overlays rendered"
