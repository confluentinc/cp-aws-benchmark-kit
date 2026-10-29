# Deployment guide

End-to-end deploy flow for a new engineer with a fresh AWS account.

## Prerequisites

### CLI tools
```bash
brew install awscli kubectl helm eksctl terraform jq python3   # macOS
# or your Linux package manager equivalent
```

### AWS account
- IAM user/role with: EKS admin, EC2 admin, Route53 admin, ELB admin, IAM admin, S3 (for TF state), DynamoDB (for TF lock)
- `aws configure sso` or `aws configure` for the profile
- **ELB quota raised to ≥100 per region** (default 50) if using Topology A — see https://console.aws.amazon.com/servicequotas/

### Repo
```bash
git clone <this-repo> cp-benchmark-kit
cd cp-benchmark-kit
make init                    # copies .env.example → .env
# Edit .env with your values
make check-prereqs           # verifies tools + AWS creds
```

## Phase 1: Terraform (AWS primitives)

```bash
make tf-remote-state-init     # one-time per account: S3 state bucket + auto-wire backends
make tf-apply-east1           # ~15 min: VPC + subnets + EKS + nodegroups + Route53 + IAM
make tf-apply-east2
make tf-output-to-env         # populates PRIVATE_SUBNETS_*, ROUTE53_ZONE_ID_*, etc. in .env
```

Review `terraform/envs/east{1,2}/terraform.tfvars.example` → copy to `terraform.tfvars` first if you want to override defaults (region, cluster name, VPC CIDR, zone name).

## Phase 2: K8s bootstrap

```bash
make bootstrap-east1    # ~15 min: kubeconfig + AWS LB Controller + CFK operator + Prometheus/Grafana + OTel + mTLS certs
make bootstrap-east2
```

Verify:
```bash
kubectl --context $KUBECTL_CONTEXT_REGION1 get pods -A
```

## Phase 3: Confluent license

```bash
make set-license LICENSE_FILE=/path/to/confluent-license.key
# Applies the Secret in both namespaces.
```

## Phase 4: Deploy Confluent Platform

```bash
make deploy-cp-east1    # ~15-20 min including broker rolling restart for mTLS
make deploy-cp-east2
```

Verify brokers Ready:
```bash
kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 get kafka
# expect: READY=15/15, STATUS=RUNNING
```

## Phase 5: Pick client-path topology (one per region)

```bash
# Topology A — 15 NLBs per broker (simpler, high ELB quota needed)
make deploy-topology-a-east1
make deploy-topology-a-east2

# OR Topology B — 3 shared NLBs + nginx-ingress (SSL passthrough + SNI)
make deploy-topology-b-east1
make deploy-topology-b-east2
```

Either triggers CFK rolling restart (~30 min) to activate the new listener config.

## Phase 6: Run the benchmark

```bash
make benchmark-build-image            # one-time: builds forked OMB → pushes to your ECR
make benchmark-pre-create-topics      # creates 150 test topics
make benchmark-ir-ab                  # full sweep: 50/100/150/200 MB/s × 4w & 8w × IR OFF & ON
make benchmark-report                 # renders perf-story.md from results/
```

## Common issues

| Problem | Fix |
|---|---|
| `TooManyLoadBalancers` on Topology A | Request ELB quota increase to 100+ per region |
| Broker CrashLoop with `No space left on device` | Increase `broker_count` / `dataVolumeCapacity` or run shorter benchmark |
| `UnknownHostException: broker-N.cl.cp...` | Route53 CNAMEs not synced — run `bash client-path/topology-*/route53-sync.sh east1` |
| OMB driver `AdminClient createTopics timeout` | Pre-create topics first: `make benchmark-pre-create-topics` |
| Grafana dashboards empty | Scrape jobs not finding targets — check pod annotations on brokers + OMB workers |
| `IntelligentReplication pusher threads = 0` | IR change needs rolling restart — `kubectl rollout restart sts kafka` (CFK sometimes doesn't bump the config hash) |

## Teardown

```bash
# Reverse order of deploy. Each step is idempotent.
make teardown-benchmark
make teardown-cp-east1
make teardown-cp-east2
make tf-destroy-east1
make tf-destroy-east2
# Finally — delete remote-state bucket if you don't need it for a redeploy
```
