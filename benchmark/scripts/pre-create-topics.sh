#!/usr/bin/env bash
# Pre-create OMB topics for the IR A/B sweep.
#
# OMB auto-creates topics via a single AdminClient.createTopics() call. At 150
# topics × 100 partitions = 15K partitions × RF=3 = 45K replicas, the controller
# can't finish within OMB's 30s request timeout → all futures hang.
#
# Workaround: pre-create the 150 topics ourselves with kafka-topics CLI (one
# create request per topic, serial, each only 100 partitions → ~300 ms each).
# OMB's createTopic() checks describeTopics first and skips if exists → the
# benchmark proceeds straight to produce/consume.
#
# Topic naming: must match the pattern OMB generates (test-topic-<uuid>). We
# use predictable names so we can delete them cleanly between runs.
#
# Usage: ./pre-create-topics.sh <count>  (default 150)
set -euo pipefail

# Load .env
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

COUNT="${1:-${BENCHMARK_TOPIC_COUNT:-150}}"
CTX="${KUBECTL_CONTEXT_REGION1}"
NS="${NAMESPACE_REGION1}"
PARTITIONS="${BENCHMARK_PARTITIONS_PER_TOPIC:-100}"
RF="${BENCHMARK_REPLICATION_FACTOR:-3}"
MIN_ISR="${BENCHMARK_MIN_ISR:-2}"
PARALLEL=10   # 10 concurrent creates — fast but safe for 15-broker cluster

echo "[$(date +%H:%M:%S)] pre-creating $COUNT topics (test-topic-ombsweep-NNN, 100p RF=3)"

kubectl --context "$CTX" -n "$NS" exec kafka-0 -c kafka -- bash -c "
PASS=\$(cat /mnt/sslcerts/jksPassword.txt | grep -oE '[^=]+\$')
cat > /tmp/admin.properties <<EOF
security.protocol=SSL
ssl.keystore.location=/mnt/sslcerts/keystore.p12
ssl.keystore.type=PKCS12
ssl.truststore.location=/mnt/sslcerts/truststore.p12
ssl.truststore.type=PKCS12
ssl.endpoint.identification.algorithm=
EOF
echo \"ssl.keystore.password=\$PASS\" >> /tmp/admin.properties
echo \"ssl.truststore.password=\$PASS\" >> /tmp/admin.properties

START=\$(date +%s)
for i in \$(seq -w 1 $COUNT); do
  kafka-topics --bootstrap-server localhost:9071 --command-config /tmp/admin.properties \
    --create --if-not-exists \
    --topic test-topic-ombsweep-\$i \
    --partitions $PARTITIONS --replication-factor $RF \
    --config min.insync.replicas=$MIN_ISR \
    > /dev/null 2>&1 &
  if (( \$(jobs -r | wc -l) >= $PARALLEL )); then wait -n; fi
done
wait
END=\$(date +%s)
TOTAL=\$(kafka-topics --bootstrap-server localhost:9071 --command-config /tmp/admin.properties --list 2>/dev/null | grep -c '^test-topic-ombsweep-')
echo \"created \$TOTAL/$COUNT topics in \$((END - START))s\"
"
echo "[$(date +%H:%M:%S)] done"
