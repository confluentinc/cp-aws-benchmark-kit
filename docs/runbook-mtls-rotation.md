# mTLS cert rotation runbook

How to rotate the self-signed CA + per-broker certs for a deployed cp-benchmark-kit cluster.

## When to rotate

- Cert expiry (default 365 days from generation)
- Compromise suspected
- Changed SAN requirements (new broker count, new domain)

## Full rotation procedure

```bash
# From repo root
cd mtls-certs

# 1. Generate fresh CA + certs (writes to /tmp/mtls-certs/)
bash 01-generate-ca-and-certs.sh

# 2. Redeploy K8s Secrets (per region)
bash 02-create-k8s-secrets.sh east1
bash 02-create-k8s-secrets.sh east2

# 3. Rolling-restart brokers to pick up new certs
kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 rollout restart statefulset kafka
kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 rollout restart statefulset kraftcontroller
# Wait for all pods to come back
kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 rollout status statefulset kafka --timeout 30m

# Same for east2
```

~30 min total per region (rolling restart). East1 and east2 can be done in parallel if cluster-link is NOT active (recommended to coordinate).

## Partial rotation (CA only, keep broker certs valid)

Not supported with the current script — the broker certs are signed by the CA, so a new CA invalidates all broker certs. Full rotation only.

## Rollback

If brokers fail to come up after rotation (cert mismatch, SAN missing):
1. Keep the previous `/tmp/mtls-certs/` snapshot before running step 1 above
2. If it still exists, re-apply the old Secret:
   ```bash
   # roll back by re-creating the Secret from the OLD files
   kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 delete secret kafka-tls
   # recreate from backup PKCS12 + old password
   kubectl --context $KUBECTL_CONTEXT_REGION1 -n $NAMESPACE_REGION1 create secret generic kafka-tls \
     --from-file=keystore.p12=/path/to/backup/kafka-east1-0.p12 \
     --from-file=cacerts.pem=/path/to/backup/ca.pem \
     --from-literal=jksPassword.txt="jksPassword=OLD_PASSWORD"
   kubectl rollout restart statefulset kafka
   ```
3. Debug the issue with the new cert, then re-run rotation

## Verify

```bash
# From an OMB worker pod (or any mTLS client):
openssl s_client -connect kafka-0.kafka.$NAMESPACE_REGION1.svc.cluster.local:9071 \
  -cert client.crt -key client.key -CAfile ca.pem </dev/null 2>&1 | grep -E 'subject|verify'
```

Expect `verify return code: 0 (ok)`.
