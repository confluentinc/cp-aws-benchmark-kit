# mtls-certs/

Self-signed CA + per-broker PKCS12 keystore generation. Ported from the original `iac/mtls/` scripts; parameterized via `.env`.

## Scripts

| | |
|---|---|
| `01-generate-ca-and-certs.sh` | Generate CA + per-broker PKCS12 keystores for both regions. SANs: `kafka-N.kafka.<namespace>.svc.cluster.local`, `*.cl.cp.<domain-region1>`, `*.cl.cp.<domain-region2>`. Writes to `/tmp/mtls-certs/`. |
| `02-create-k8s-secrets.sh <east1\|east2>` | Create K8s Secrets (`kafka-tls`, `kraft-tls`, `client-tls-{admin,producer,consumer}`) in the target cluster's namespace. |

## Flow

```bash
# From repo root:
bash mtls-certs/01-generate-ca-and-certs.sh     # one-time: generates all certs
bash mtls-certs/02-create-k8s-secrets.sh east1
bash mtls-certs/02-create-k8s-secrets.sh east2
```

Or just use `make bootstrap-east1` / `make bootstrap-east2` — it calls these in order.

## Cert rotation

Regenerate CA + certs by re-running `01` (writes new timestamp-based keystore password to `/tmp/mtls-certs/jksPassword.txt`). Then re-run `02` for each region to update the Secrets. Brokers pick up the new cert on next pod restart (no automatic reload — safest to rolling-restart via `kubectl -n <ns> rollout restart statefulset kafka`).

## Needing changes for cp-benchmark-kit integration

The current scripts have hardcoded values (`cflt-east1`, `cflt-east2`, `kafka-east1-0..14`, etc.) that need to be sourced from `.env`:
- `BROKER_COUNT`
- `DOMAIN_REGION1` / `DOMAIN_REGION2`
- `NAMESPACE_REGION1` / `NAMESPACE_REGION2`
- `KUBECTL_CONTEXT_REGION1` / `KUBECTL_CONTEXT_REGION2`

**TODO:** Parameterize the three scripts. For now they work as-is for the original cluster names; copy them to the new repo and the engineer will adapt. See `../bootstrap/04-mtls-certs.sh` for the wrapper that passes region keys.

## Cert SAN list (current)

Each broker PKCS12 keystore has these SANs:
- `kafka-N.kafka.<namespace>.svc.cluster.local` (per-broker pod DNS, N=0..14)
- `kafka.<namespace>.svc.cluster.local` (headless Service DNS)
- `kafka` (short name)
- `localhost`
- `*.cl.cp.<domain-region1>` (wildcard — covers bootstrap, broker0..N, b0..bN, bootstrap-ext)
- `*.cl.cp.<domain-region2>` (same, for cross-region)
