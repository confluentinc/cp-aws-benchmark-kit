#!/usr/bin/env bash
# Delete + recreate all ombsweep topics for a clean baseline between runs.
# Usage: ./recreate-topics.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

COUNT="${BENCHMARK_TOPIC_COUNT:-150}"
CTX="${KUBECTL_CONTEXT_REGION1}"
NS="${NAMESPACE_REGION1}"
PARTITIONS="${BENCHMARK_PARTITIONS_PER_TOPIC:-100}"
RF="${BENCHMARK_REPLICATION_FACTOR:-3}"
MIN_ISR="${BENCHMARK_MIN_ISR:-2}"

echo "[$(date +%H:%M:%S)] deleting + recreating $COUNT test-topic-ombsweep-* topics..."
kubectl --context "$CTX" -n "$NS" exec kafka-0 -c kafka -- env COUNT="$COUNT" PARTITIONS="$PARTITIONS" RF="$RF" MIN_ISR="$MIN_ISR" bash -c '
PASS=$(cat /mnt/sslcerts/jksPassword.txt | grep -oE "[^=]+$")
cat > /tmp/admin.properties <<EOFCFG
security.protocol=SSL
ssl.keystore.location=/mnt/sslcerts/keystore.p12
ssl.keystore.type=PKCS12
ssl.truststore.location=/mnt/sslcerts/truststore.p12
ssl.truststore.type=PKCS12
ssl.endpoint.identification.algorithm=
EOFCFG
echo "ssl.keystore.password=$PASS" >> /tmp/admin.properties
echo "ssl.truststore.password=$PASS" >> /tmp/admin.properties
# Delete all $COUNT in parallel
for i in $(seq -w 1 $COUNT); do
  kafka-topics --bootstrap-server localhost:9071 --command-config /tmp/admin.properties \
    --delete --topic test-topic-ombsweep-$i > /dev/null 2>&1 &
  if (( $(jobs -r | wc -l) >= 10 )); then wait -n; fi
done
wait
# Recreate all $COUNT in parallel
for i in $(seq -w 1 $COUNT); do
  kafka-topics --bootstrap-server localhost:9071 --command-config /tmp/admin.properties \
    --create --if-not-exists --topic test-topic-ombsweep-$i \
    --partitions $PARTITIONS --replication-factor $RF --config min.insync.replicas=$MIN_ISR > /dev/null 2>&1 &
  if (( $(jobs -r | wc -l) >= 10 )); then wait -n; fi
done
wait
READY=$(kafka-topics --bootstrap-server localhost:9071 --command-config /tmp/admin.properties --list | grep -c "^test-topic-ombsweep-")
echo "  ready: $READY/$COUNT topics"
'
echo "[$(date +%H:%M:%S)] done"
