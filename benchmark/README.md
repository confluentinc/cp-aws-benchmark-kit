# benchmark/

OpenMessaging Benchmark (OMB) harness for Kafka throughput + latency sweeps.

## Layout

```
benchmark/
├── omb/                        # Dockerfile for the forked OMB image
├── workloads/                  # (reserved for workload templates)
├── k8s/
│   ├── 01-configmap.yaml.tpl   # ConfigMap: driver-kafka.yaml + workload YAMLs
│   ├── 02-worker-sts.yaml.tpl  # OMB worker StatefulSet (replicas + heap configurable)
│   └── drivers/
│       ├── driver-150t-50mb.yaml.tpl   # one-shot Job per throughput
│       ├── driver-150t-100mb.yaml.tpl
│       ├── driver-150t-150mb.yaml.tpl
│       └── driver-150t-200mb.yaml.tpl
├── scripts/
│   ├── pre-create-topics.sh    # create 150 test topics (idempotent)
│   ├── recreate-topics.sh      # delete + recreate (clean baseline between runs)
│   ├── metrics-capture.sh      # Prometheus queries over benchmark window → metrics.json
│   └── run-sweep.sh            # orchestrator: launches drivers sequentially + captures
└── results/                    # output: {phase}/{throughput}mb/{result.json,metrics.json,job-logs.txt}
```

## Workflow

```bash
# One-time:
make benchmark-build-image      # build+push forked OMB image (needs openmessaging-benchmark/ submodule)

# Per benchmark session:
make benchmark-pre-create-topics  # creates 150 test-topic-ombsweep-{001..150}
make benchmark-ir-ab              # full sweep: 50/100/150/200 MB/s × 4w & 8w, IR OFF then ON
make benchmark-report             # renders perf-story.md from results/
```

## Reconfigure for a different workload shape

Edit `.env`:
```
BENCHMARK_TOPIC_COUNT=150        # or 50, or 500
BENCHMARK_PARTITIONS_PER_TOPIC=100
BENCHMARK_MESSAGE_SIZE_BYTES=1024
BENCHMARK_WARMUP_MINUTES=1
BENCHMARK_TEST_MINUTES=5
```

Then re-render the configmap:
```bash
envsubst < k8s/01-configmap.yaml.tpl | kubectl apply -f -
```

## Templates (ported from original scattered repo)

These were previously hardcoded to:
- namespace `cflt-east1`
- bootstrap `kafka-N.kafka.<namespace>.svc.cluster.local:9071` OR `bootstrap-ext.<your-domain>:443`
- OMB image `<your-account>.dkr.ecr.<region>.amazonaws.com/cp-benchmark/omb:0.3.0-xregion-arm64`
- worker URL list `omb-worker-ir-sweep-0..7`

In this consolidated repo, each template file uses placeholders that `run-sweep.sh` (and other scripts) substitute from `.env` values via `envsubst`. **TODO:** parameterize the `.tpl` files — currently they still contain the original hardcoded values. Easy sed replacement when migrating fully.

## Results archive

`benchmark/results/` is gitignored. After a sweep, zip and attach to Claude artifact chat (see `../docs/runbook-benchmark.md` for the Claude prompt).
