#!/usr/bin/env bash
# bootstrap/04-mtls-certs.sh — generate CA + per-broker PKCS12 keystores
# and deploy as K8s Secrets. Thin wrapper around mtls-certs/01..03.sh.
#
# Idempotent: safe to re-run. On re-run, regenerates certs with current .env
# values and redeploys the Secrets (brokers pick up on next pod restart).
#
# Usage: bash bootstrap/04-mtls-certs.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/.env"

echo "[$(date +%H:%M:%S)] mTLS cert generation + deployment for ${REGION_KEY}"
echo "  BROKER_COUNT=$BROKER_COUNT"
echo "  DOMAIN_REGION1=$DOMAIN_REGION1"
echo "  DOMAIN_REGION2=$DOMAIN_REGION2"

# Only generate CA + certs once (first region triggers it; second region reuses the same CA).
# The actual script already handles this by checking if CA files exist.
bash "$REPO_ROOT/mtls-certs/01-generate-ca-and-certs.sh"
bash "$REPO_ROOT/mtls-certs/02-create-k8s-secrets.sh" "$REGION_KEY"

echo "✓ mTLS Secrets deployed for $REGION_KEY"
echo
echo "Note: the Kafka CR itself must reference these Secrets. The confluent/base/kafka.yaml"
echo "      is already wired to use them (secretName: kafka-pkcs12 for brokers,"
echo "      kraft-pkcs12 for controllers). Run 'make deploy-cp-$REGION_KEY' next."
