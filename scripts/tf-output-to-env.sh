#!/usr/bin/env bash
# Pull Terraform outputs from envs/east1 and envs/east2 and update .env.
#
# Updates these keys (idempotent — safe to re-run):
#   PRIVATE_SUBNETS_REGION1 / 2
#   PUBLIC_SUBNETS_REGION1 / 2
#   NGINX_INGRESS_SUBNETS_REGION1 / 2
#   ROUTE53_ZONE_ID_REGION1 / 2
#   DOMAIN_REGION1 / 2
#
# Usage (from repo root): make tf-output-to-env
#                   OR:   bash scripts/tf-output-to-env.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_FILE="$REPO_ROOT/.env"

[[ ! -f "$ENV_FILE" ]] && { echo "ERROR: $ENV_FILE missing. Run 'make init' first."; exit 1; }

update_env_key() {
  local key=$1 value=$2
  # Replace line "KEY=..." with "KEY=<value>". Create if missing.
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm "${ENV_FILE}.bak"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  echo "  set ${key}=${value}"
}

pull_region() {
  local region=$1 env_dir=$2 key_suffix=$3
  echo "→ Pulling TF outputs from ${env_dir}..."

  if [[ ! -d "$REPO_ROOT/terraform/envs/${env_dir}/.terraform" ]]; then
    echo "  SKIP: ${env_dir} not initialized (run 'terraform init' + 'terraform apply' first)"
    return
  fi

  pushd "$REPO_ROOT/terraform/envs/${env_dir}" >/dev/null

  local tf_out
  if ! tf_out=$(terraform output -json 2>/dev/null); then
    echo "  SKIP: ${env_dir} has no outputs yet (not applied?)"
    popd >/dev/null
    return
  fi

  local private_subnets
  private_subnets=$(echo "$tf_out" | jq -r '.private_subnet_ids.value | join(",")')
  update_env_key "PRIVATE_SUBNETS_REGION${key_suffix}" "$private_subnets"

  local public_subnets
  public_subnets=$(echo "$tf_out" | jq -r '.public_subnet_ids.value | join(",")')
  update_env_key "PUBLIC_SUBNETS_REGION${key_suffix}" "$public_subnets"

  local nginx_subnets
  nginx_subnets=$(echo "$tf_out" | jq -r '.nginx_ingress_subnet_ids.value | join(",")')
  update_env_key "NGINX_INGRESS_SUBNETS_REGION${key_suffix}" "$nginx_subnets"

  local zone_id
  zone_id=$(echo "$tf_out" | jq -r '.route53_zone_id.value')
  update_env_key "ROUTE53_ZONE_ID_REGION${key_suffix}" "$zone_id"

  local zone_name
  zone_name=$(echo "$tf_out" | jq -r '.route53_zone_name.value')
  # strip trailing dot that AWS adds
  zone_name="${zone_name%.}"
  update_env_key "DOMAIN_REGION${key_suffix}" "$zone_name"

  popd >/dev/null
}

pull_region east1 east1 1
pull_region east2 east2 2

echo
echo "✓ .env updated. Review:"
echo
grep -E '^(PRIVATE_SUBNETS|PUBLIC_SUBNETS|NGINX_INGRESS_SUBNETS|ROUTE53_ZONE_ID|DOMAIN)_REGION[12]=' "$ENV_FILE" | sort
