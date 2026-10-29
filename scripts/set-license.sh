#!/usr/bin/env bash
# Apply the Confluent Platform license as a K8s Secret in both regions.
# CFK pods will NOT start without this — easy to miss on first deploy.
#
# Usage: bash scripts/set-license.sh <path/to/license.key>
#    or: LICENSE_FILE=/path/to/license.key bash scripts/set-license.sh

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

LICENSE_FILE="${1:-${LICENSE_FILE:-}}"
if [[ -z "$LICENSE_FILE" ]]; then
  cat <<EOF
Usage: bash scripts/set-license.sh <path/to/license.key>

The Confluent Platform license file is a text file provided by Confluent
Sales. Example contents:
  licenseVersion: 1
  licenseType: enterprise
  licenseExpirationDate: ...
  ...

Without this, CFK broker pods will CrashLoopBackOff on startup.
EOF
  exit 1
fi

[[ ! -f "$LICENSE_FILE" ]] && { echo "✗ License file not found: $LICENSE_FILE"; exit 1; }

for region_key in east1 east2; do
  case "$region_key" in
    east1) CTX=$KUBECTL_CONTEXT_REGION1; NS=$NAMESPACE_REGION1 ;;
    east2) CTX=$KUBECTL_CONTEXT_REGION2; NS=$NAMESPACE_REGION2 ;;
  esac

  echo "[$region_key] applying $CONFLUENT_LICENSE_SECRET_NAME to $NS on $CTX"
  kubectl --context "$CTX" -n "$NS" create secret generic "$CONFLUENT_LICENSE_SECRET_NAME" \
    --from-file=license=$LICENSE_FILE \
    --dry-run=client -o yaml | \
    kubectl --context "$CTX" apply -f -
done

echo "✓ Confluent license applied in both regions"
