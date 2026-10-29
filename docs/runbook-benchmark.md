# Benchmark runbook

How to run the OpenMessaging Benchmark (OMB) sweep against a deployed cp-benchmark-kit cluster.

## Pre-flight

```bash
# From repo root
make check-prereqs
kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 get kafka   # expect 15/15 Ready
```

## Build + push forked OMB image (one-time)

```bash
make benchmark-build-image
# Pushes ${OMB_IMAGE} (defined in .env)
```

## Pre-create topics (first run only; or after `make benchmark-recreate-topics`)

```bash
make benchmark-pre-create-topics
# Creates 150 topics: test-topic-ombsweep-{001..150}, each 100 partitions, RF=3, min.ISR=2
```

## Run the IR A/B sweep

```bash
make benchmark-ir-ab
# Sequence:
#   1. recreate-topics (clean baseline)
#   2. deploy driver-150t-50mb (6 min: 1 warmup + 5 test)
#   3. capture metrics → results/ir-off/50mb/
#   4. recreate-topics
#   5. driver-150t-100mb → results/ir-off/100mb/
#   6. ... (150, 200 MB/s 4w, 200 MB/s 8w)
#   7. Toggle IR → rolling restart (~30 min)
#   8. Repeat all 5 workloads under IR ON
```

Full sweep takes ~2.5 hours (including the IR flip rolling restart).

## Run the Topology A vs Topology B comparison (IR ON only)

```bash
# First deploy Topology A, run sweep, then switch to Topology B and run again.
make deploy-topology-a-east1
make benchmark-ir-ab      # saves to results/topology-a/
# Switch:
make deploy-topology-b-east1   # triggers rolling restart (~30 min)
make benchmark-ir-ab      # saves to results/topology-b/
```

## Analysis

```bash
make benchmark-report
# Reads results/{ir-off,ir-on,topology-a,topology-b}/*/result.json + metrics.json
# Renders docs/perf-story.md with:
#   - Headline latency matrix
#   - Full percentile distribution (p50 / p99 / p999 / p9999 / max)
#   - Broker + OMB worker + node resource comparison
#   - Consumer-side details (lag, fetch latency, commit latency)
#   - Appended Claude artifact prompt
```

## Claude artifact prompt (for interactive dashboard)

See `../templates/claude-artifact-prompt.md` for the standalone prompt you can paste into a fresh Claude chat along with a zip of `results/`. Will generate a React single-page comparison dashboard.

## What the metrics capture collects (per run)

`metrics-capture.sh` queries Prometheus over the exact benchmark window and captures:

**Brokers** (per pod + cluster aggregate):
- CPU avg/max cores
- JVM heap used GB
- JVM threads
- Produce p99 TotalTime (ms)
- Produce p99 RemoteTime (ms)
- Request handler idle %
- UnderReplicatedPartitions
- ISR shrinks

**OMB workers** (per pod + cluster aggregate):
- Pod CPU avg/max cores
- JVM heap used GB
- JVM threads
- Record send rate
- Request latency avg/max ms
- Record error rate

**Consumers**:
- Records consumed rate
- Bytes consumed MB/s
- Fetch latency avg/max ms
- Fetch size avg bytes
- Records-lag-max
- Commit latency avg ms

**Nodes** (via node_exporter):
- Broker nodes CPU% / mem% / net RX/TX MB/s
- OMB nodes CPU% / mem% / net RX/TX MB/s

Output: `results/<phase>/<throughput>mb/{result.json, metrics.json, job-logs.txt}`

## Topic cleanup between runs

Topics MUST be deleted + recreated between runs. Otherwise consumer with `auto.offset.reset=earliest` would read accumulated historical data from prior runs, inflating E2E latency figures by orders of magnitude.

The sweep orchestrator does this automatically. Manual between-run cleanup:
```bash
make benchmark-recreate-topics
```

## Common issues

See `deployment-guide.md` "Common issues" table.
