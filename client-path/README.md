# client-path/

Two client-path topologies for OMB / production clients → Kafka brokers. Pick ONE per region.

## Comparison

| | Topology A | Topology B |
|---|---|---|
| Pattern | CFK `externalAccess: {type: loadBalancer}` on CLUSTERLINK listener | CFK `externalAccess: {type: staticForHostBasedRouting}` on EXTERNAL listener |
| NLB count per region | 15 broker NLBs + 1 bootstrap = 16 | 3 (one per AZ) |
| Intermediate hop | None (NLB → broker) | nginx-ingress (SSL passthrough + SNI) |
| TLS termination | Broker | Broker (nginx is passthrough) |
| ELB quota impact | High | Low |
| Added client latency | None | ~0.5-1 ms Pub p99 |
| Setup complexity | Simpler | More moving pieces |
| Suitable for | Internal / same-VPC clients | External clients / cross-account via TGW |

Both terminate mTLS at the broker.

## Deploying

```bash
# From repo root
make deploy-topology-a-east1       # OR topology-b-east1
make deploy-topology-a-east2       # OR topology-b-east2
```

See each subdirectory's README for details.

## Can I switch later?

Yes — the Kafka CR change is additive and requires a rolling restart (~30 min). To switch:
1. `kubectl kustomize client-path/topology-X/overlay/east1 | kubectl apply -f -`
2. CFK operator reconciles → rolling restart begins
3. After rolling restart, run `client-path/topology-X/route53-sync.sh east1` to update DNS

The old topology's NLBs are not auto-deleted — remove them manually if no longer needed.
