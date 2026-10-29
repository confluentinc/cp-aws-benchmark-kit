# cp-benchmark-kit

Reproducible 2-region Confluent Platform benchmark cluster on AWS EKS, with:
- 15 brokers per region (r7g.8xlarge, KRaft, mTLS on 4 listeners)
- Bidirectional Cluster Link (east1 ↔ east2)
- **Two client-path topologies** to compare:
  - **Topology A** — 15 NLBs per pod (CFK default `loadBalancer`)
  - **Topology B** — 3 shared NLBs + nginx-ingress (SSL passthrough + SNI)
- OpenMessaging Benchmark (OMB) harness with 150-topic / 15K-partition workloads
- Full observability: kube-prometheus-stack + Grafana (8 custom dashboards) + OTel + Tempo + Jaeger

Driven by a single `.env` file. Every AWS/K8s identifier is parameterized.

---

## 5-minute deploy (new engineer, fresh AWS account)

```bash
# Prereqs: aws, kubectl, helm, eksctl, terraform, jq, python3
git clone <this-repo> cp-benchmark-kit
cd cp-benchmark-kit

make init                       # copy .env.example → .env, open and fill in
make check-prereqs              # verify CLI tools + AWS credentials + .env completeness

# 1. Infra (Terraform — AWS primitives only)
make tf-remote-state-init       # one-time: creates S3 state bucket + auto-wires envs/*/backend.tf
make tf-apply-east1             # ~15 min: VPC + subnets + EKS + nodegroups + Route53 + IAM
make tf-apply-east2
make tf-output-to-env           # populates PRIVATE_SUBNETS_* and ROUTE53_ZONE_ID_* in .env

# 2. K8s bootstrap (post-TF installs)
make bootstrap-east1            # AWS LB Controller + CFK operator + monitoring + mTLS certs
make bootstrap-east2

# 3. Confluent license (CFK pods won't start without this)
make set-license LICENSE_FILE=/path/to/confluent-license.key

# 4. Confluent Platform
make deploy-cp-east1            # Kafka + KRaft + CC + SR + Connect + KsqlDB + Rest + Cluster Link
make deploy-cp-east2
# Wait ~15-20 min for brokers Ready

# 4. Observability
make deploy-observability-east1
make deploy-observability-east2

# 5. Client-path topology — pick ONE per region
make deploy-topology-a-east1    # 15 NLBs per broker (default CFK pattern)
# OR
make deploy-topology-b-east1    # 3 shared NLBs + nginx-ingress (SSL passthrough)

# 6. Benchmark
# ONE-TIME: clone upstream OMB into benchmark/omb/ (the kit does not vendor it):
#   cd benchmark/omb
#   git clone https://github.com/openmessaging/openmessaging-benchmark.git
#   cd ../..
# For 150+ topic scale testing, see benchmark/omb/fork-notes.md for a 2-line patch to apply.
make benchmark-build-image      # one-time: build + push OMB image to your ECR
make benchmark-pre-create-topics
make benchmark-ir-ab            # full IR OFF vs IR ON sweep (~90 min for all throughputs)
make benchmark-report           # renders perf-story.md from benchmark/results/
```

Full `make help` shows every target with a one-line description.

---

## Repo layout

```
cp-benchmark-kit/
├── README.md                   ← you are here
├── .env.example                ← ALL parameters in one place
├── Makefile                    ← one-line targets, delegates to scripts
├── docs/                       ← architecture, deployment guide, runbooks
├── terraform/                  ← AWS primitives (VPC/EKS/nodegroups/Route53/IAM)
│   ├── modules/                ← reusable TF modules
│   └── envs/{east1,east2}/     ← per-region TF root
├── bootstrap/                  ← K8s installs (AWS LB Controller, CFK, monitoring, certs)
├── confluent/                  ← Kustomize for all CP CRs (base + 2 overlays)
├── cluster-link/               ← bidirectional CL (base + 2 overlays)
├── client-path/
│   ├── topology-a-nlb-per-pod/
│   └── topology-b-nginx-ingress/
├── observability/              ← kube-prometheus-stack values + 8 dashboards + OTel stack
├── benchmark/
│   ├── omb/                    ← Dockerfile for the forked image
│   ├── workloads/              ← OMB workload templates (throughput-parameterized)
│   ├── k8s/                    ← OMB STS, driver jobs, configmaps (templated)
│   └── scripts/                ← topic recreate, metrics capture, sweep orchestrator
├── latency-probes/             ← OPTIONAL Spring Boot + OTel E2E probes
└── mtls-certs/                 ← CA + per-broker PKCS12 generation (parameterized)
```

---

## Decision tree — which client-path topology?

Both are supported; pick based on your production reference:

| Factor | Topology A (NLB per pod) | Topology B (shared NLB + nginx-ingress) |
|---|---|---|
| NLB count | 15 per broker + bootstrap = 16 per region | 3 per region (1 per AZ) |
| ELB quota impact | High (watch out for per-region quota) | Low |
| Added TCP hop | None | 1 (nginx SSL passthrough) |
| mTLS termination | Broker | Broker (nginx is passthrough) |
| Observed Pub p99 overhead vs direct-pod-DNS | — | ~+0.5-1 ms |
| Setup complexity | Simpler (just CFK `externalAccess: loadBalancer`) | More moving pieces (nginx + Ingress + SNI) |

See `docs/architecture.md` for details.

---

## What's optional

- **Topology A vs B** — pick one; both don't need to coexist.
- **Cluster Link to east2** — can run single-region (just skip east2 TF + bootstrap).
- **OTel + Tempo + Jaeger** — tracing stack is optional; omit if you only need Prometheus metrics.
- **Spring Boot latency probes** (`latency-probes/`) — organic client-side latency measurement; use when OMB alone isn't enough.
- **IR (Intelligent Replication)** — defaults to ON; toggle via `.env` + `make deploy-cp-*`.

---

## Benchmark artifact (perf-story)

After a benchmark sweep, `make benchmark-report` renders a markdown report with:
- Headline latency matrix (per throughput, per IR state, per topology)
- Full percentile distribution (p50/p99/p999/p9999/max)
- Resource utilization (brokers, OMB workers, nodes)
- Consumer-side metrics (lag, fetch latency, commit latency)
- Appended Claude artifact prompt for interactive dashboard generation

See `docs/runbook-benchmark.md` for the full flow.

---

## Documentation

| | |
|---|---|
| `docs/architecture.md` | 2-region topology, IR explanation, both client-paths, listener/port map |
| `docs/deployment-guide.md` | Phase-by-phase deploy flow, prereqs, quota requirements |
| `docs/runbook-benchmark.md` | Running the OMB sweep, interpreting results |
| `docs/runbook-mtls-rotation.md` | Cert renewal procedure |
