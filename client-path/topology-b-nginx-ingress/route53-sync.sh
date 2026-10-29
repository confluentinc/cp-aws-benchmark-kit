#!/usr/bin/env bash
# Topology B — Route53 sync. UPSERT weighted alias A records for:
#   bootstrap-ext.<domain>  → round-robin across 3 nginx NLBs
#   b{0..N-1}.<domain>      → round-robin across 3 nginx NLBs
#
# Each name has 3 alias records (one per NLB, equal weight) + EvaluateTargetHealth
# so Route53 automatically routes away from a dead NLB.
#
# Usage: bash client-path/topology-b-nginx-ingress/route53-sync.sh <east1|east2>

set -euo pipefail
REGION_KEY="${1:?Usage: $0 <east1|east2>}"
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

case "$REGION_KEY" in
  east1)
    CONTEXT=$KUBECTL_CONTEXT_REGION1
    NAMESPACE=$NAMESPACE_REGION1
    ZONE_ID=$ROUTE53_ZONE_ID_REGION1
    DOMAIN=$DOMAIN_REGION1
    NLB_HOSTED_ZONE=$NLB_HOSTED_ZONE_REGION1
    ;;
  east2)
    CONTEXT=$KUBECTL_CONTEXT_REGION2
    NAMESPACE=$NAMESPACE_REGION2
    ZONE_ID=$ROUTE53_ZONE_ID_REGION2
    DOMAIN=$DOMAIN_REGION2
    NLB_HOSTED_ZONE=$NLB_HOSTED_ZONE_REGION2
    ;;
  *) echo "Unknown region: $REGION_KEY"; exit 1 ;;
esac

[[ -z "$ZONE_ID" ]] && { echo "ERROR: ROUTE53_ZONE_ID_* missing in .env"; exit 1; }

echo "[$(date +%H:%M:%S)] Topology B Route53 sync for ${REGION_KEY} (domain: ${DOMAIN})"

BROKER_COUNT_LIVE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get sts kafka -o jsonpath='{.spec.replicas}')

NLB_A=$(kubectl --context "$CONTEXT" -n ingress-nginx get svc nginx-zone-a-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_B=$(kubectl --context "$CONTEXT" -n ingress-nginx get svc nginx-zone-b-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_C=$(kubectl --context "$CONTEXT" -n ingress-nginx get svc nginx-zone-c-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

for v in NLB_A NLB_B NLB_C; do
  [[ -z "${!v}" ]] && { echo "ERROR: $v hostname missing — nginx not up yet"; exit 1; }
done
echo "  NLB_A=$NLB_A"
echo "  NLB_B=$NLB_B"
echo "  NLB_C=$NLB_C"

PAYLOAD=/tmp/r53-topology-b-${REGION_KEY}.json
echo '{"Comment": "cp-benchmark-kit Topology B sync", "Changes": [' > "$PAYLOAD"
first=1

NAMES=("bootstrap-ext")
for i in $(seq 0 $((BROKER_COUNT_LIVE - 1))); do NAMES+=("b${i}"); done

for name in "${NAMES[@]}"; do
  idx=0
  for nlb in "$NLB_A" "$NLB_B" "$NLB_C"; do
    case $idx in 0) set_id="zone-a";; 1) set_id="zone-b";; 2) set_id="zone-c";; esac
    [[ $first -eq 0 ]] && echo "," >> "$PAYLOAD"
    cat >> "$PAYLOAD" <<EOF
{"Action":"UPSERT","ResourceRecordSet":{"Name":"${name}.${DOMAIN}","Type":"A","SetIdentifier":"${set_id}","Weight":1,"AliasTarget":{"HostedZoneId":"${NLB_HOSTED_ZONE}","DNSName":"${nlb}","EvaluateTargetHealth":true}}}
EOF
    first=0
    idx=$((idx+1))
  done
done
echo "]}" >> "$PAYLOAD"

change_id=$(aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --change-batch "file://$PAYLOAD" --profile "$AWS_PROFILE" --query 'ChangeInfo.Id' --output text)

for i in 1 2 3 4 5 6; do
  status=$(aws route53 get-change --id "$change_id" --profile "$AWS_PROFILE" --query 'ChangeInfo.Status' --output text)
  [[ "$status" == "INSYNC" ]] && { echo "  ✓ INSYNC"; break; }
  sleep 10
done

echo "✓ Topology B DNS synced for $REGION_KEY"
