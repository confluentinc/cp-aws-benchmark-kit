#!/usr/bin/env bash
# bootstrap/00-kubeconfig.sh — update ~/.kube/config with EKS cluster credentials.
#
# Usage: bash bootstrap/00-kubeconfig.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1) AWS_REGION=$REGION1; CLUSTER=$CLUSTER_NAME_REGION1; CONTEXT=$KUBECTL_CONTEXT_REGION1 ;;
  east2) AWS_REGION=$REGION2; CLUSTER=$CLUSTER_NAME_REGION2; CONTEXT=$KUBECTL_CONTEXT_REGION2 ;;
  *) echo "Unknown region key: $REGION_KEY"; exit 1 ;;
esac

echo "[$(date +%H:%M:%S)] Updating kubeconfig for ${CLUSTER} in ${AWS_REGION} (context: ${CONTEXT})"
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER" \
  --alias "$CONTEXT" \
  --profile "$AWS_PROFILE"

kubectl --context "$CONTEXT" get nodes
echo "✓ kubeconfig for $REGION_KEY ready"
