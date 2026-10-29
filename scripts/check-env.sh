#!/usr/bin/env bash
# Preflight validator: verify .env is fully populated with real values (not
# placeholder defaults). Fails fast with a clear list of what's wrong.
#
# Called by `make check-prereqs`.

set -uo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

[[ ! -f "$REPO_ROOT/.env" ]] && { echo "✗ $REPO_ROOT/.env missing. Run: make init"; exit 1; }
source "$REPO_ROOT/.env"

errors=()

# ─── Required at all times ───
for var in AWS_ACCOUNT_ID AWS_PROFILE REGION1 REGION2 \
           CLUSTER_NAME_REGION1 CLUSTER_NAME_REGION2 \
           KUBECTL_CONTEXT_REGION1 KUBECTL_CONTEXT_REGION2 \
           NAMESPACE_REGION1 NAMESPACE_REGION2 \
           VPC_CIDR_REGION1 VPC_CIDR_REGION2 \
           DOMAIN_REGION1 DOMAIN_REGION2 \
           BROKER_COUNT BROKER_INSTANCE \
           OMB_IMAGE CONFLUENT_LICENSE_SECRET_NAME; do
  val="${!var:-}"
  [[ -z "$val" ]] && errors+=("$var is empty")
done

# ─── Must not be the .env.example placeholders ───
check_not_placeholder() {
  local var=$1 placeholder=$2
  local val="${!var:-}"
  if [[ "$val" == "$placeholder" ]]; then
    errors+=("$var still has placeholder value: '$placeholder'")
  fi
}
check_not_placeholder AWS_ACCOUNT_ID       "123456789012"
check_not_placeholder AWS_PROFILE          "my-profile"
check_not_placeholder DOMAIN_REGION1       "cl.cp.east1.example.internal"
check_not_placeholder DOMAIN_REGION2       "cl.cp.east2.example.internal"

# ─── Required after `make tf-apply-*` ───
# (warn, don't block, since these are populated later in the flow)
warnings=()
for var in PRIVATE_SUBNETS_REGION1 PRIVATE_SUBNETS_REGION2 \
           NGINX_INGRESS_SUBNETS_REGION1 NGINX_INGRESS_SUBNETS_REGION2 \
           ROUTE53_ZONE_ID_REGION1 ROUTE53_ZONE_ID_REGION2; do
  val="${!var:-}"
  [[ -z "$val" ]] && warnings+=("$var is empty (populated by: make tf-output-to-env)")
done

# ─── Report ───
if [[ ${#errors[@]} -gt 0 ]]; then
  echo "✗ .env has ${#errors[@]} problem(s):"
  for e in "${errors[@]}"; do echo "    - $e"; done
  echo
  echo "  Edit $REPO_ROOT/.env and re-run: make check-prereqs"
  exit 1
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
  echo "⚠  .env has ${#warnings[@]} warning(s) — fine for early phases:"
  for w in "${warnings[@]}"; do echo "    - $w"; done
  echo
fi

echo "✓ .env OK ($(grep -c '^[A-Z]' "$REPO_ROOT/.env") vars defined, 0 placeholders remaining)"
