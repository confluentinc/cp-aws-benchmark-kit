#!/usr/bin/env bash
# Benchmark sweep orchestrator. For each throughput:
#   recreate topics → render templates → kubectl apply driver → wait → capture
#
# Phases:
#   ir-ab        → IR OFF sweep + flip IR ON (requires rolling restart) + IR ON sweep
#   ir-on        → IR ON only, 5 throughputs (50/100/150/200 MB/s 4w + 200 MB/s 8w)
#   ir-off       → IR OFF only
#   topology-ab  → Topology A sweep + switch to Topology B + Topology B sweep (IR ON)
#   single <mb> <w>  → Just one run (debugging; passes throughput + worker count)
#
# Usage: bash benchmark/scripts/run-sweep.sh <phase> [throughput_mb] [workers]
#   examples:
#     bash run-sweep.sh ir-on                   # full IR ON sweep
#     bash run-sweep.sh single 200 4            # just 200 MB/s with 4 workers

set -uo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

PHASE="${1:-ir-on}"
RESULTS="$REPO_ROOT/benchmark/results"
CTX="${KUBECTL_CONTEXT_REGION1}"
NS="${NAMESPACE_REGION1}"
SCRIPTS="$REPO_ROOT/benchmark/scripts"
RENDERED=/tmp/omb-rendered

# ─── Helpers ───

wait_for_job() {
  local job=$1
  echo "[$(date +%H:%M:%S)] waiting for job/$job ..."
  while true; do
    local jobst
    jobst=$(kubectl --context "$CTX" -n "$NS" get job "$job" -o jsonpath='{.status.succeeded}{"/"}{.status.failed}' 2>/dev/null)
    if [[ "$jobst" == "1/" || "$jobst" == "1/0" ]]; then
      echo "[$(date +%H:%M:%S)] $job SUCCEEDED"
      return 0
    elif [[ "${jobst#*/}" != "" && "${jobst#*/}" != "0" ]]; then
      echo "[$(date +%H:%M:%S)] $job FAILED (status=$jobst)"
      return 1
    fi
    sleep 30
  done
}

run_single() {
  local phase_tag=$1 mbs=$2 workers=$3 suffix=${4:-}

  echo
  echo "=== $phase_tag: $mbs MB/s with $workers workers ==="

  # Recreate topics for clean baseline
  bash "$SCRIPTS/recreate-topics.sh" | tail -3

  # Render templates for THIS throughput + worker count
  bash "$SCRIPTS/render-templates.sh" "$mbs" "$workers"

  # Ensure OMB STS scaled correctly
  kubectl --context "$CTX" apply -f "$RENDERED/02-worker-sts.yaml"
  kubectl --context "$CTX" -n "$NS" rollout status statefulset omb-worker-ir-sweep --timeout 10m

  # Ensure configmap applied
  kubectl --context "$CTX" apply -f "$RENDERED/01-configmap.yaml"

  # Launch driver
  local job="omb-driver-150t-${mbs}mb"
  kubectl --context "$CTX" -n "$NS" delete job "$job" --ignore-not-found >/dev/null 2>&1
  kubectl --context "$CTX" apply -f "$RENDERED/drivers/driver-150t-${mbs}mb.yaml"

  wait_for_job "$job"

  # Capture metrics
  bash "$SCRIPTS/metrics-capture.sh" "$phase_tag" "$mbs"

  # Rename folder if suffix given (for 4workers vs 8workers)
  if [[ -n "$suffix" ]]; then
    local src="$RESULTS/${phase_tag}/${mbs}mb"
    local dst="$RESULTS/${phase_tag}/${mbs}mb_${suffix}"
    rm -rf "$dst"
    mv "$src" "$dst"
    echo "  moved → $dst"
  fi
}

run_sweep() {
  local phase_tag=$1
  run_single "$phase_tag"  50 4
  run_single "$phase_tag" 100 4
  run_single "$phase_tag" 150 4
  run_single "$phase_tag" 200 4 "4workers"
  run_single "$phase_tag" 200 8 "8workers"
}

toggle_ir() {
  local enable=$1   # true or false
  echo
  echo "=== Toggling IR to: $enable (requires rolling restart ~30 min) ==="
  kubectl --context "$CTX" -n "$NS" patch kafka kafka --type merge \
    --patch "{\"spec\":{\"configOverrides\":{\"server\":[\"confluent.intelligent.replication.enable=$enable\"]}}}"
  # CFK doesn't always auto-roll on this change — force it:
  kubectl --context "$CTX" -n "$NS" rollout restart statefulset kafka
  kubectl --context "$CTX" -n "$NS" rollout status statefulset kafka --timeout 45m
}

# ─── Main ───

case "$PHASE" in
  single)
    MBS="${2:?Usage: run-sweep.sh single <mb> <workers>}"
    WORKERS="${3:?Usage: run-sweep.sh single <mb> <workers>}"
    run_single "manual" "$MBS" "$WORKERS"
    ;;
  ir-on)
    run_sweep ir-on
    ;;
  ir-off)
    run_sweep ir-off
    ;;
  ir-ab)
    toggle_ir false
    run_sweep ir-off
    toggle_ir true
    run_sweep ir-on
    ;;
  topology-ab)
    echo "Topology A sweep (requires Topology A already deployed)"
    run_sweep topology-a
    echo "Switch to Topology B now via 'make deploy-topology-b-east1' then re-run this script with topology-b"
    ;;
  topology-a|topology-b)
    run_sweep "$PHASE"
    ;;
  *)
    echo "Unknown phase: $PHASE"
    echo "Usage: $0 <ir-off|ir-on|ir-ab|topology-a|topology-b|topology-ab|single>"
    exit 1
    ;;
esac

echo
echo "=== SWEEP COMPLETE ($PHASE) ==="
ls -la "$RESULTS/$PHASE/" 2>/dev/null || ls -la "$RESULTS/"
