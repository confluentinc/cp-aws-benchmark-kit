#!/usr/bin/env bash
# observability/install.sh — wraps bootstrap/03-monitoring.sh (which already does
# the full install flow). This file exists so that `make deploy-observability-*`
# has a single entry point for just the observability layer (vs the full bootstrap).

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec bash "$REPO_ROOT/bootstrap/03-monitoring.sh" "$REGION_KEY"
