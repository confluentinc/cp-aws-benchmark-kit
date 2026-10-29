#!/usr/bin/env bash
# bootstrap/01-core-addons.sh — install AWS Load Balancer Controller + metrics-server.
#
# EBS CSI driver is already installed by the eks-cluster TF module (as an EKS addon).
# AWS LB Controller requires a Helm install + IRSA role (role is created by iam-irsa TF module).
#
# Usage: bash bootstrap/01-core-addons.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1)
    AWS_REGION=$REGION1
    CLUSTER=$CLUSTER_NAME_REGION1
    CONTEXT=$KUBECTL_CONTEXT_REGION1
    VPC_ID_OUTPUT_FROM_TF=$(cd "$REPO_ROOT/terraform/envs/east1" && terraform output -raw vpc_id 2>/dev/null || echo "")
    LB_ROLE_ARN=$(cd "$REPO_ROOT/terraform/envs/east1" && terraform output -raw aws_lb_controller_role_arn 2>/dev/null || echo "")
    ;;
  east2)
    AWS_REGION=$REGION2
    CLUSTER=$CLUSTER_NAME_REGION2
    CONTEXT=$KUBECTL_CONTEXT_REGION2
    VPC_ID_OUTPUT_FROM_TF=$(cd "$REPO_ROOT/terraform/envs/east2" && terraform output -raw vpc_id 2>/dev/null || echo "")
    LB_ROLE_ARN=$(cd "$REPO_ROOT/terraform/envs/east2" && terraform output -raw aws_lb_controller_role_arn 2>/dev/null || echo "")
    ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

[[ -z "$LB_ROLE_ARN" ]] && { echo "ERROR: aws_lb_controller_role_arn not available from TF — run tf-apply first"; exit 1; }
[[ -z "$VPC_ID_OUTPUT_FROM_TF" ]] && { echo "ERROR: vpc_id not available from TF"; exit 1; }

echo "[$(date +%H:%M:%S)] Installing AWS Load Balancer Controller on ${CLUSTER}"
echo "  LB Controller role ARN: ${LB_ROLE_ARN}"
echo "  VPC ID: ${VPC_ID_OUTPUT_FROM_TF}"

# ─── Install AWS Load Balancer Controller ───
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null

# Create ServiceAccount with IRSA role annotation
kubectl --context "$CONTEXT" -n kube-system create serviceaccount aws-load-balancer-controller \
  --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

kubectl --context "$CONTEXT" -n kube-system annotate serviceaccount aws-load-balancer-controller \
  "eks.amazonaws.com/role-arn=$LB_ROLE_ARN" --overwrite

helm --kube-context "$CONTEXT" upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID_OUTPUT_FROM_TF" \
  --wait --timeout 5m

# ─── metrics-server (for kubectl top) ───
echo "[$(date +%H:%M:%S)] Installing metrics-server"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update metrics-server >/dev/null
helm --kube-context "$CONTEXT" upgrade --install metrics-server \
  metrics-server/metrics-server \
  -n kube-system \
  --wait --timeout 2m

echo "✓ Core addons installed on $REGION_KEY"
kubectl --context "$CONTEXT" -n kube-system get pods | grep -E 'aws-load-balancer|metrics-server' || true
