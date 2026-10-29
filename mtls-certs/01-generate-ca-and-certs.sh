#!/usr/bin/env bash
# Generate a self-signed CA + per-broker + per-client certs + JKS keystore/truststore
# bundles for mTLS on Confluent Platform.
#
# Output: /tmp/mtls-certs/
#   ca.crt, ca.key                     — root CA (private, keep safe)
#   truststore.p12                     — contains ca.crt, used by every broker + client
#   kafka-east1-N.p12  (N=0..14)       — per-broker keystore east1
#   kafka-east2-N.p12  (N=0..14)       — per-broker keystore east2
#   kraft-east1-N.p12  (N=0..2)        — KRaft controller keystores east1
#   kraft-east2-N.p12  (N=0..2)        — KRaft controller keystores east2
#   client-admin.p12                   — admin client cert (CN=admin, super user if ACLs ON)
#   client-producer.p12                — producer app cert (CN=producer)
#   client-consumer.p12                — consumer app cert (CN=consumer)
#   jksPassword.txt                    — single password for everything (test env; use Vault in prod)
#
# All certs CN=<identity>, principal mapping on broker: RULE:.*CN[\s]?=[\s]?([a-zA-Z0-9.-]*)?.*/$1/
# → principal becomes the CN. So "CN=producer" → user name "producer" (used in super.users).

set -euo pipefail

# Load .env for cluster-specific values
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ -f "$REPO_ROOT/.env" ]] && source "$REPO_ROOT/.env"

# Required .env values (with sensible fallbacks for safe generation)
BROKER_COUNT=${BROKER_COUNT:-15}
CONTROLLER_COUNT=${CONTROLLER_COUNT:-3}
NAMESPACE_REGION1=${NAMESPACE_REGION1:-cflt-east1}
NAMESPACE_REGION2=${NAMESPACE_REGION2:-cflt-east2}
# For wildcard SANs: strip the first label (e.g. "cl.cp.east1.example.internal" → "cl.cp.east1.example.internal")
# We cover the FULL domain pattern since broker hostnames resolve to b{N}.<domain> or broker{N}.<domain>.
DOMAIN_REGION1=${DOMAIN_REGION1:-cl.cp.east1.example.internal}
DOMAIN_REGION2=${DOMAIN_REGION2:-cl.cp.east2.example.internal}

OUT=${OUT:-/tmp/mtls-certs}
PASS=${PASS:-"confluent-mtls-$(date +%s)"}
VALID_DAYS=${VALID_DAYS:-825}  # ≤825 for Apple keystores; adjust for prod

mkdir -p "$OUT"
cd "$OUT"
echo "$PASS" > jksPassword.txt
chmod 600 jksPassword.txt

echo "=== Output dir: $OUT ==="
echo "=== Password written to: $OUT/jksPassword.txt ==="
echo

# ────────────────────────────────────────────────────────────────────────────────
# Step 1: Self-signed CA
# ────────────────────────────────────────────────────────────────────────────────
if [[ ! -f ca.key ]]; then
  echo "[1/4] Creating self-signed CA..."
  openssl genrsa -out ca.key 4096
  openssl req -new -x509 -key ca.key -sha256 -days "$VALID_DAYS" \
    -subj "/C=US/ST=CA/O=Confluent/CN=Confluent CFK Test CA" \
    -out ca.crt
  echo "  ✓ ca.crt, ca.key created"
else
  echo "[1/4] ca.key already exists, reusing"
fi

# ────────────────────────────────────────────────────────────────────────────────
# Step 2: Common truststore (contains the CA cert)
# ────────────────────────────────────────────────────────────────────────────────
echo "[2/4] Building common truststore.p12..."
rm -f truststore.p12
keytool -import -file ca.crt -alias confluent-ca -keystore truststore.p12 \
  -storetype PKCS12 -storepass "$PASS" -noprompt
echo "  ✓ truststore.p12 ($(ls -la truststore.p12 | awk '{print $5}') bytes)"

# ────────────────────────────────────────────────────────────────────────────────
# Step 3: Per-broker + per-controller + per-client keystores
# ────────────────────────────────────────────────────────────────────────────────
make_keystore() {
  local name=$1       # e.g. kafka-east1-0, kraft-east1-1, client-producer
  local cn=$2         # Subject CN
  local sans=$3       # Comma-separated SANs (DNS/IP)

  rm -f "${name}.p12" "${name}.csr" "${name}.crt" "${name}.key"

  openssl genrsa -out "${name}.key" 2048 >/dev/null 2>&1
  openssl req -new -key "${name}.key" -subj "/CN=${cn}" -out "${name}.csr" >/dev/null 2>&1

  cat > "${name}.ext" <<EOF
subjectAltName = ${sans}
extendedKeyUsage = serverAuth,clientAuth
EOF
  openssl x509 -req -in "${name}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out "${name}.crt" -days "$VALID_DAYS" -sha256 -extfile "${name}.ext" >/dev/null 2>&1

  openssl pkcs12 -export -in "${name}.crt" -inkey "${name}.key" -CAfile ca.crt \
    -chain -name "${cn}" -out "${name}.p12" -passout pass:"$PASS" >/dev/null 2>&1
  rm -f "${name}.csr" "${name}.ext" "${name}.key" "${name}.crt"
  echo "  ✓ ${name}.p12 (CN=${cn})"
}

echo "[3/4] Generating per-broker + per-KRaft keystores..."
# NOTE: SANs must cover both the in-cluster K8s DNS (kafka-N.kafka.NS.svc.cluster.local)
# AND the Cluster Linking LB hostnames (bootstrap.<domain-region>,
# brokerN.<domain-region>). Wildcard *.<domain-region>
# covers both bootstrap and per-broker LB hostnames in a single entry so the cert
# doesn't need regenerating when broker count changes.
# Without the CL SANs, kafka REST (which validates certs via standard TLS hostname
# verification) rejects the CLUSTERLINK bootstrap with
#   java.security.cert.CertificateException: No subject alternative DNS name matching
#   bootstrap.<domain-region2> found
# when the operator tries to create the ClusterLink CR.
# Wildcard SANs cover bootstrap, broker0..N, b0..bN under each region's domain in a
# single entry — no cert regen when broker count changes.
CL_SANS="DNS:*.${DOMAIN_REGION1},DNS:*.${DOMAIN_REGION2}"

# east1 kafka brokers
for i in $(seq 0 $((BROKER_COUNT - 1))); do
  make_keystore "kafka-east1-${i}" "kafka-east1-${i}" \
    "DNS:kafka-${i}.kafka.${NAMESPACE_REGION1}.svc.cluster.local,DNS:kafka,DNS:localhost,${CL_SANS}"
done
# east2 kafka brokers
for i in $(seq 0 $((BROKER_COUNT - 1))); do
  make_keystore "kafka-east2-${i}" "kafka-east2-${i}" \
    "DNS:kafka-${i}.kafka.${NAMESPACE_REGION2}.svc.cluster.local,DNS:kafka,DNS:localhost,${CL_SANS}"
done
# east1 KRaft controllers
for i in $(seq 0 $((CONTROLLER_COUNT - 1))); do
  make_keystore "kraft-east1-${i}" "kraft-east1-${i}" \
    "DNS:kraftcontroller-${i}.kraftcontroller.${NAMESPACE_REGION1}.svc.cluster.local,DNS:kraftcontroller"
done
# east2 KRaft controllers
for i in $(seq 0 $((CONTROLLER_COUNT - 1))); do
  make_keystore "kraft-east2-${i}" "kraft-east2-${i}" \
    "DNS:kraftcontroller-${i}.kraftcontroller.${NAMESPACE_REGION2}.svc.cluster.local,DNS:kraftcontroller"
done

# ────────────────────────────────────────────────────────────────────────────────
# Step 4: Client keystores (apps use these to connect to brokers)
# ────────────────────────────────────────────────────────────────────────────────
echo "[4/4] Generating client keystores..."
make_keystore "client-admin"    "admin"    "DNS:client-admin"
make_keystore "client-producer" "producer" "DNS:client-producer"
make_keystore "client-consumer" "consumer" "DNS:client-consumer"

echo
echo "============================================================"
echo "Done. Artifacts in $OUT:"
ls -la "$OUT" | grep -E '\.(p12|crt|key|txt)$'
echo
echo "Password: $PASS   (also in $OUT/jksPassword.txt)"
echo "Next: run ./02-create-k8s-secrets.sh"
echo "============================================================"
