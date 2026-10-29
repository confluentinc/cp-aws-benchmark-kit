#!/usr/bin/env bash
# render-templates.sh — generate deployable K8s manifests from .env + templates.
#
# Reads .env and writes rendered YAML to /tmp/omb-rendered/:
#   01-configmap.yaml        # driver-kafka.yaml + per-throughput workloads + topicNames list
#   02-worker-sts.yaml       # worker STS with correct replicas + heap
#   drivers/driver-150t-{Nmb}.yaml   # one driver per throughput, correct worker URLs
#
# All workload YAML content and the topicNames list are generated from .env values
# (BENCHMARK_TOPIC_COUNT, BENCHMARK_PARTITIONS_PER_TOPIC, BENCHMARK_MESSAGE_SIZE_BYTES,
# BENCHMARK_WARMUP_MINUTES, BENCHMARK_TEST_MINUTES).
#
# Usage:
#   bash benchmark/scripts/render-templates.sh                  # render all workloads at 4w/32G heap
#   bash benchmark/scripts/render-templates.sh 200 8            # render only 200 MB/s driver, STS at 8w/40G heap

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

ONLY_MBS="${1:-all}"
WORKER_COUNT="${2:-4}"

# ─── Defaults from .env ───
export NAMESPACE="${NAMESPACE:-$NAMESPACE_REGION1}"
export BENCHMARK_TOPIC_COUNT="${BENCHMARK_TOPIC_COUNT:-150}"
export BENCHMARK_PARTITIONS_PER_TOPIC="${BENCHMARK_PARTITIONS_PER_TOPIC:-100}"
export BENCHMARK_REPLICATION_FACTOR="${BENCHMARK_REPLICATION_FACTOR:-3}"
export BENCHMARK_MIN_ISR="${BENCHMARK_MIN_ISR:-2}"
export BENCHMARK_MESSAGE_SIZE_BYTES="${BENCHMARK_MESSAGE_SIZE_BYTES:-1024}"
export BENCHMARK_WARMUP_MINUTES="${BENCHMARK_WARMUP_MINUTES:-1}"
export BENCHMARK_TEST_MINUTES="${BENCHMARK_TEST_MINUTES:-5}"
export JMX_EXPORTER_VERSION="${JMX_EXPORTER_VERSION:-0.20.0}"

# OMB STS sizing
export OMB_WORKER_REPLICAS="$WORKER_COUNT"
if [[ "$WORKER_COUNT" -ge 8 ]]; then
  export OMB_WORKER_HEAP="-Xms20G -Xmx40G"
else
  export OMB_WORKER_HEAP="-Xms16G -Xmx32G"
fi

# Worker URL list
URLS=""
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  URLS+="http://omb-worker-ir-sweep-${i}.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080"
  [[ $i -lt $((WORKER_COUNT - 1)) ]] && URLS+=","
done
export OMB_WORKER_URLS="$URLS"

# Bootstrap (default to pod-DNS; .env can override for Topology A/B)
if [[ -z "${OMB_BOOTSTRAP_SERVERS:-}" ]]; then
  export OMB_BOOTSTRAP_SERVERS="kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9071,kafka-1.kafka.${NAMESPACE}.svc.cluster.local:9071,kafka-2.kafka.${NAMESPACE}.svc.cluster.local:9071"
fi
export OMB_SSL_ENDPOINT_ID_ALGORITHM="${OMB_SSL_ENDPOINT_ID_ALGORITHM:-}"

# Throughputs to render (MB/s → records/s uses message size)
THROUGHPUTS=(50 100 150 200)
if [[ "$ONLY_MBS" != "all" ]]; then
  THROUGHPUTS=("$ONLY_MBS")
fi

OUT=/tmp/omb-rendered
rm -rf "$OUT"
mkdir -p "$OUT/drivers"

# ─── Generate topicNames list (JSON array as YAML inline list) ───
TOPIC_NAMES_JSON=$(python3 -c "
import json
count = int('$BENCHMARK_TOPIC_COUNT')
names = [f'test-topic-ombsweep-{i:03d}' for i in range(1, count + 1)]
print(json.dumps(names))
")

# ─── Generate per-throughput workload YAML entries ───
WORKLOAD_ENTRIES=""
for mbs in "${THROUGHPUTS[@]}"; do
  # records/sec = mbs * 1024 * 1024 / BENCHMARK_MESSAGE_SIZE_BYTES
  rec_s=$(python3 -c "print(int($mbs * 1024 * 1024 / $BENCHMARK_MESSAGE_SIZE_BYTES))")
  WORKLOAD_ENTRIES+="
  workload-150t-100p-1kb-${mbs}mb.yaml: |
    name: ${mbs} MB/s | ${BENCHMARK_TOPIC_COUNT}t x ${BENCHMARK_PARTITIONS_PER_TOPIC}p | ${BENCHMARK_MESSAGE_SIZE_BYTES}B | ${rec_s} rec/s | ${BENCHMARK_TEST_MINUTES}min
    topics: ${BENCHMARK_TOPIC_COUNT}
    partitionsPerTopic: ${BENCHMARK_PARTITIONS_PER_TOPIC}
    messageSize: ${BENCHMARK_MESSAGE_SIZE_BYTES}
    useRandomizedPayloads: true
    randomBytesRatio: 0.5
    randomizedPayloadPoolSize: 1000
    subscriptionsPerTopic: 1
    consumerPerSubscription: 2
    producersPerTopic: 1
    producerRate: ${rec_s}
    consumerBacklogSizeGB: 0
    testDurationMinutes: ${BENCHMARK_TEST_MINUTES}
    warmupDurationMinutes: ${BENCHMARK_WARMUP_MINUTES}
    topicNames: ${TOPIC_NAMES_JSON}
"
done
export __WORKLOAD_ENTRIES__="$WORKLOAD_ENTRIES"

echo "[$(date +%H:%M:%S)] Rendering → $OUT"
echo "  NAMESPACE=$NAMESPACE"
echo "  OMB_IMAGE=$OMB_IMAGE"
echo "  OMB_WORKER_REPLICAS=$OMB_WORKER_REPLICAS  HEAP=$OMB_WORKER_HEAP"
echo "  BOOTSTRAP=$OMB_BOOTSTRAP_SERVERS"
echo "  TOPICS=$BENCHMARK_TOPIC_COUNT × ${BENCHMARK_PARTITIONS_PER_TOPIC}p"
echo "  Throughputs: ${THROUGHPUTS[*]}"

# ─── Render configmap ───
envsubst '${NAMESPACE} ${BENCHMARK_REPLICATION_FACTOR} ${BENCHMARK_MIN_ISR} ${OMB_BOOTSTRAP_SERVERS} ${OMB_SSL_ENDPOINT_ID_ALGORITHM} ${__WORKLOAD_ENTRIES__}' \
  < "$REPO_ROOT/benchmark/k8s/01-configmap.yaml.tpl" > "$OUT/01-configmap.yaml"

# ─── Render worker STS ───
envsubst '${NAMESPACE} ${OMB_IMAGE} ${OMB_WORKER_REPLICAS} ${OMB_WORKER_HEAP} ${JMX_EXPORTER_VERSION}' \
  < "$REPO_ROOT/benchmark/k8s/02-worker-sts.yaml.tpl" > "$OUT/02-worker-sts.yaml"

# ─── Render driver jobs ───
for mbs in "${THROUGHPUTS[@]}"; do
  tpl="$REPO_ROOT/benchmark/k8s/drivers/driver-150t-${mbs}mb.yaml.tpl"
  if [[ -f "$tpl" ]]; then
    sed "s|--workers http://omb-worker-ir-sweep-0[^[:space:]]*|--workers ${OMB_WORKER_URLS}|g" "$tpl" | \
      envsubst '${NAMESPACE} ${OMB_IMAGE}' > "$OUT/drivers/driver-150t-${mbs}mb.yaml"
  fi
done

echo "✓ Rendered:"
ls "$OUT" "$OUT/drivers" 2>&1
