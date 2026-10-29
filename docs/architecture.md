# Architecture

Reference architecture for a 2-region Confluent Platform benchmark cluster on AWS EKS.

## High-level topology

```
    ┌─────────────── region 1 (us-east-1) ─────────────┐    ┌──── region 2 (us-east-2) ────┐
    │                                                   │    │                               │
    │  EKS cluster                                      │    │  EKS cluster                  │
    │  ├── ng-base (t3.medium × 1)                      │    │  ├── ng-base                  │
    │  ├── ng-brokers (r7g.8xlarge × 15, 1-per-node)   │    │  ├── ng-brokers (15)          │
    │  ├── ng-controllers (3)                           │    │  ├── ng-controllers (3)       │
    │  ├── ng-omb-clients (c7gn.8xlarge × 10)          │    │  ├── ng-omb-clients           │
    │  └── ng-ingress-xl (c7gn.2xlarge × 3)             │    │  └── ng-ingress-xl            │
    │       (optional — Topology B only)                │    │                               │
    │                                                   │    │                               │
    │  Confluent Platform (via CFK)                     │    │  Confluent Platform           │
    │  ├── Kafka (15 brokers, 5 listeners, mTLS 4/5)   │    │  ├── Kafka                    │
    │  ├── KRaft Controllers (3, dedicated)             │    │  ├── KRaft Controllers        │
    │  ├── Control Center / SR / Connect / KsqlDB / Rest│    │  └── (same CP components)     │
    │  └── Cluster Link (east1 → east2, bidirectional)  │ ↔ │                               │
    │                                                   │    │                               │
    │  Observability                                    │    │                               │
    │  ├── kube-prometheus-stack (Prom + Grafana)       │    │  (same stack)                 │
    │  ├── OTel Collector → Tempo + Jaeger (tracing)   │    │                               │
    │  └── JMX exporters on brokers + OMB workers       │    │                               │
    │                                                   │    │                               │
    │  Benchmark                                        │    │                               │
    │  └── OMB (10 workers + driver jobs + sweep)       │    │                               │
    │                                                   │    │                               │
    └───────────────────────────────────────────────────┘    └───────────────────────────────┘
```

## Broker setup

| | |
|---|---|
| Deployment | Confluent for Kubernetes (CFK) operator, Helm-managed |
| Confluent Platform | `cp-server:8.3.1` (configurable via `.env`) |
| KRaft mode | Yes — split topology: 3 dedicated KRaft controllers + 15 brokers (as observers) |
| Broker instance | r7g.8xlarge (32 vCPU, 256 GiB, 15 Gbps, Graviton3) |
| Broker pod | request 18.1 CPU / 100 GiB, limit 20 CPU / 100 GiB |
| Broker heap | `-Xms32G -Xmx32G` (JVM) |
| Broker storage | 1024 GiB EBS gp3 per broker |
| Replica placement | 1 broker per node (`oneReplicaPerNode: true`) |

## Listeners (all 5 use mTLS except CLUSTERLINK)

| Listener | Port | Protocol | Purpose |
|---|---|---|---|
| INTERNAL | 9071 | SSL / mTLS | Admin, bootstrap for in-cluster clients |
| EXTERNAL | 9092 | SSL / mTLS | Client access (via NLB — see Client-path topologies below) |
| REPLICATION | 9072 | SSL / mTLS | Inter-broker replication |
| CONTROLLER | 9074 | SSL / mTLS | KRaft controller plane |
| CLUSTERLINK | 9098 | PLAINTEXT | Cluster-link traffic only (dedicated listener) |

**mTLS principal mapping:** `RULE:.*CN[\s]?=[\s]?([a-zA-Z0-9.-]*)?.*/$1/`

See `mtls-certs/README.md` for the cert generation flow (CA + per-broker PKCS12 keystores).

## Client-path topologies

Both are supported. Pick one per region via `make deploy-topology-{a,b}-east{1,2}`.

### Topology A — NLB per pod

```
Client → DNS: broker{N}.cl.cp.east1.example.internal
       → per-broker internal NLB (one per broker + 1 bootstrap = 16 NLBs per region)
       → broker pod (mTLS termination)
```

- Uses CFK's `externalAccess: {type: loadBalancer}` on the CLUSTERLINK listener
- 15 broker NLBs + 1 bootstrap NLB = 16 NLBs per region
- No intermediate hop — pure NLB forwarding
- **Watch out:** AWS default ELB quota is 50 per region; 2-region setup needs quota raised to 100+

### Topology B — Shared NLB + nginx-ingress

```
Client → DNS: b{N}.cl.cp.east1.example.internal
       → one of 3 per-AZ internal NLBs (DNS round-robin)
       → nginx-ingress-controller (SSL passthrough — SNI-routed)
       → kafka-{N}-internal ClusterIP Service
       → broker pod (mTLS termination)
```

- Uses CFK's `externalAccess: {type: staticForHostBasedRouting}` on the EXTERNAL listener
- 3 NLBs per region (one per AZ)
- nginx on `c7gn.2xlarge × 3` (one per AZ, 7000m CPU limit each)
- **Added overhead:** ~0.5-1 ms Pub p99, ~1 ms E2E p99 vs Topology A (measured at 50-200 MB/s)
- mTLS still terminates at the broker (nginx is passthrough)

## Cluster Link (bidirectional)

| | |
|---|---|
| Topology | east1 ↔ east2 (one `ClusterLink` CR per direction) |
| Listener | PLAINTEXT CLUSTERLINK on :9098 (mTLS deferred due to CFK Kafka REST SNI issue) |
| Mirror prefix | `cflt-east2-` on east1 (mirrors from east2); `cflt-east1-` on east2 |
| Auto-create filter | INCLUDE `test-topic-*` |
| Fetchers | `num.cluster.link.fetchers=16` |
| Fetch tuning | `replica.fetch.max.bytes=10 MiB`, `replica.fetch.wait.max.ms=5` |

## Intelligent Replication (IR)

- Config: `confluent.intelligent.replication.enable` (static broker config in Kafka CR)
- Default: ON (`.env` has `INTELLIGENT_REPLICATION_ENABLED=true`)
- **Enable requires rolling restart** — CFK dynamic config change doesn't instantiate pusher threads
- Verify active via Prometheus: `sum(kafka_server_pusher_thread_metrics_connection_count)` > 0

## Observability

### Prometheus / Grafana
- `kube-prometheus-stack` Helm chart
- Scrape jobs: `cfk-jmx` (brokers), `kafka-client-jmx` (OMB workers), `node-exporter`, `cp-flink` (if present)
- Native histograms + remote-write receiver enabled
- Grafana sidecar auto-provisions dashboards from ConfigMaps labeled `grafana_dashboard=1`

### Grafana dashboards (8 included)
1. Confluent Platform overview
2. Kafka broker tuning
3. Kafka producer performance (client-side)
4. Kafka consumer performance (client-side)
5. Kafka cluster linking
6. Kafka cluster aggregate
7. OMB consumer deep-dive
8. Latency probe OTel (optional)

### OTel / Tempo / Jaeger
- OTel Collector in `monitoring` namespace, OTLP gRPC :4317 / HTTP :4318
- Exports to Tempo (primary trace backend) + Jaeger (parallel for comparison)
- Memory limiter + batch processor
- Optional for benchmark; required if using Spring Boot latency probes

## Benchmark harness (OMB)

### Image
- Forked from upstream OpenMessaging Benchmark
- Adds `topicNames: [...]` field to workload YAML (enables pre-created topic use — avoids `createTopics` timeout at 150+ topics)
- Multi-arch build (arm64 for Graviton); image: `${ECR}/cp-benchmark/omb:0.3.0-xregion-arm64`

### Workload defaults
| Parameter | Value |
|---|---|
| Topics | 150 (`test-topic-ombsweep-001..150`) |
| Partitions per topic | 100 |
| Total partitions | 15,000 |
| Replication factor | 3 (= 45,000 replica slots) |
| min.insync.replicas | 2 |
| Message size | 1 KiB |
| Compression | zstd |
| Warmup | 1 min |
| Test duration | 5 min |
| Throughput tiers | 50 / 100 / 150 / 200 MB/s |
| Worker counts | 4 or 8 |

### Metrics capture
- `benchmark/scripts/metrics-capture.sh` — Prometheus queries over the exact benchmark window
- Captures broker CPU/heap/listeners, OMB worker CPU/heap/threads, consumer lag/commit/fetch, nodes
- Output: `benchmark/results/<phase>/<throughput>mb/{result.json, metrics.json, job-logs.txt}`

## File reuse (what was ported from the original scattered repo)

See `../plan.md` (if present) for the full "critical files to preserve" mapping. High-level:
- Confluent CRs → `confluent/base/` + Kustomize overlays
- Shell scripts (mTLS, Route53, benchmark orchestration) → parameterized versions in their respective folders
- Grafana dashboards → `observability/grafana-dashboards/` (JSON files unchanged)
- OMB workloads + K8s manifests → `benchmark/` as templates
