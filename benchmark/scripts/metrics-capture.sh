#!/usr/bin/env bash
# Thorough OMB IR A/B capture — one call pulls everything.
# Usage: ./metrics-capture.sh <ir-off|ir-on> <50|100|200|300>

set -uo pipefail
PHASE="${1:-}"; MBS="${2:-}"
[[ -z "$PHASE" || -z "$MBS" ]] && { echo "Usage: $0 <phase> <mbs>  (phase=ir-off|ir-on|topology-a|topology-b, mbs=50|100|150|200)" >&2; exit 1; }

# Load .env
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

OUT="$REPO_ROOT/benchmark/results/${PHASE}/${MBS}mb"
JOB="omb-driver-150t-${MBS}mb"
mkdir -p "$OUT"

CTX="${KUBECTL_CONTEXT_REGION1}"
NS="${NAMESPACE_REGION1}"
NS_MON="${MONITORING_NAMESPACE:-monitoring}"
PROM_PORT=19090

echo "[$(date +%H:%M:%S)] capturing: phase=$PHASE mbs=$MBS → $OUT"

# ─── 1. Pull OMB job logs + result ───
kubectl --context "$CTX" -n "$NS" logs job/"$JOB" >"$OUT/job-logs.txt" 2>&1 || true
awk '/FULL_RESULT_JSON_START/,/FULL_RESULT_JSON_END/' "$OUT/job-logs.txt" | sed '1d;$d' >"$OUT/result.json"
[[ -s "$OUT/result.json" ]] && echo "  ✓ result.json ($(wc -c <"$OUT/result.json") bytes)" || echo "  ✗ result.json empty"

# ─── 2. Port-forward Prometheus ───
pkill -f "port-forward.*${PROM_PORT}:" 2>/dev/null; sleep 1
kubectl --context "$CTX" -n "$NS_MON" port-forward svc/kps-kube-prometheus-stack-prometheus "${PROM_PORT}:9090" >/tmp/pf-prom.log 2>&1 &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT
for i in 1 2 3 4 5; do
  curl -sf --max-time 3 "http://localhost:${PROM_PORT}/-/healthy" >/dev/null && break
  sleep 2
done

# ─── 3. Python does: date parsing, host-IP discovery, all queries, summary ───
python3 <<PYEOF >"$OUT/metrics.json"
import json, re, subprocess, urllib.parse, datetime, sys

OUT = "$OUT"
PHASE, MBS = "$PHASE", $MBS

# ── Parse test window from job logs ──
with open(f"{OUT}/job-logs.txt") as f:
    logs = f.read()

def parse_date(line):
    # "=== starting benchmark at Thu Oct 22 06:46:38 PM UTC 2026 ==="
    m = re.search(r'at ([A-Z][a-z]+ [A-Z][a-z]+ +\d+ +\d+:\d+:\d+ [AP]M UTC \d{4})', line)
    if m: return datetime.datetime.strptime(m.group(1), "%a %b %d %I:%M:%S %p UTC %Y").replace(tzinfo=datetime.timezone.utc)
    m = re.search(r'at ([A-Z][a-z]+ [A-Z][a-z]+ +\d+ +\d+:\d+:\d+ UTC \d{4})', line)
    if m: return datetime.datetime.strptime(m.group(1), "%a %b %d %H:%M:%S UTC %Y").replace(tzinfo=datetime.timezone.utc)
    return None

# Use benchmark-traffic window (excludes warmup) when available
start_dt, end_dt = None, None
for line in logs.splitlines():
    if "Starting benchmark traffic" in line:
        # time is at start of line: "18:47:46.290 [main] INFO ..."
        m = re.match(r'(\d{2}:\d{2}:\d{2})', line)
        if m:
            # need a date too - get from "starting benchmark at" line
            bm = re.search(r'starting benchmark at ([A-Z][a-z]+ [A-Z][a-z]+ +\d+)', logs)
            if bm:
                date_prefix = bm.group(1)  # "Thu Oct 22"
                # year from log
                yr = re.search(r'UTC (\d{4})', logs)
                year = yr.group(1) if yr else datetime.datetime.now().year
                start_dt = datetime.datetime.strptime(f"{date_prefix} {year} {m.group(1)}", "%a %b %d %Y %H:%M:%S").replace(tzinfo=datetime.timezone.utc)
                # end = start + 5 min (test duration)
                end_dt = start_dt + datetime.timedelta(minutes=5)
                break

if not start_dt:
    # Fallback: use "BENCHMARK DONE" minus 5 min, or last 10 min
    for line in logs.splitlines():
        if "BENCHMARK DONE" in line:
            end_dt = parse_date(line)
            if end_dt: start_dt = end_dt - datetime.timedelta(minutes=5); break

if not start_dt:
    end_dt = datetime.datetime.now(datetime.timezone.utc)
    start_dt = end_dt - datetime.timedelta(minutes=10)

START, END = int(start_dt.timestamp()), int(end_dt.timestamp())
print(f'# test window: {start_dt.isoformat()} → {end_dt.isoformat()} ({(END-START)//60} min)', file=sys.stderr)

# ── PromQL helpers ──
def q(query, start=START, end=END, step=30):
    url = f"http://localhost:${PROM_PORT}/api/v1/query_range?query={urllib.parse.quote(query)}&start={start}&end={end}&step={step}"
    try:
        out = subprocess.run(["curl","-s","--max-time","25",url], capture_output=True, text=True).stdout
        return json.loads(out)
    except Exception as e:
        return {"error": str(e)}

def qi(query, time=END):
    url = f"http://localhost:${PROM_PORT}/api/v1/query?query={urllib.parse.quote(query)}&time={time}"
    try:
        return json.loads(subprocess.run(["curl","-s","--max-time","15",url], capture_output=True, text=True).stdout)
    except Exception as e: return {"error": str(e)}

def summarize(resp, key="pod"):
    series = {}
    for item in resp.get("data", {}).get("result", []):
        labels = item.get("metric", {})
        vals = [float(v[1]) for v in item.get("values", []) if v[1] not in ("NaN","+Inf","-Inf")]
        if not vals: continue
        k = labels.get(key, labels.get("kubernetes_pod_name", labels.get("instance", labels.get("client_id", "unknown"))))
        if k in series:
            # multiple series for same key: take max avg
            if sum(vals)/len(vals) < series[k]["avg"]: continue
        series[k] = {"avg": round(sum(vals)/len(vals), 3), "max": round(max(vals), 3), "min": round(min(vals), 3), "samples": len(vals)}
    return series

def agg(d):
    if not d: return None
    avgs = [v["avg"] for v in d.values()]
    maxs = [v["max"] for v in d.values()]
    return {"per_pod": d, "cluster_sum_avg": round(sum(avgs),3), "cluster_max": round(max(maxs),3), "cluster_avg": round(sum(avgs)/len(avgs),3), "pod_count": len(d)}

# ── Discover host IPs for brokers + workers (for node metric filter) ──
def hosts_for(pod_regex, ns):
    r = qi(f'kube_pod_info{{pod=~"{pod_regex}", namespace="{ns}"}}')
    ips = sorted({x.get("metric",{}).get("host_ip","") for x in r.get("data",{}).get("result",[]) if x.get("metric",{}).get("host_ip")})
    return ips

broker_hosts = hosts_for("kafka-[0-9]+", "${NS}")
omb_hosts = hosts_for("omb-worker-ir-sweep-.*", "${NS}")
print(f'# broker hosts: {len(broker_hosts)}, omb hosts: {len(omb_hosts)}', file=sys.stderr)

def regex_hosts(hosts, port=9100):
    # PromQL regex: use [.] instead of \. to avoid escaping headaches with
    # Python f-strings → URL encode → Prometheus's quoted-string regex parser.
    def to_regex(h): return h.replace(".", "[.]") + f":{port}"
    return "|".join(to_regex(h) for h in hosts) if hosts else "none"

broker_re = regex_hosts(broker_hosts)
omb_re = regex_hosts(omb_hosts)

# ── Build result ──
result = {
    "phase": PHASE, "throughput_mbs": MBS,
    "window": {"start": start_dt.isoformat(), "end": end_dt.isoformat(), "duration_min": round((END-START)/60, 1)},
    "topology": {"broker_hosts": broker_hosts, "omb_hosts": omb_hosts},
}

# ═══════ BROKERS (east1, 15 pods) ═══════
B = result["brokers_east1"] = {}
B["cpu_cores"]          = agg(summarize(q('sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="${NS}", pod=~"kafka-[0-9]+", container="kafka"}[1m]))')))
B["mem_working_gb"]     = agg(summarize(q('container_memory_working_set_bytes{namespace="${NS}", pod=~"kafka-[0-9]+", container="kafka"} / 1024 / 1024 / 1024')))
B["jvm_heap_used_gb"]   = agg(summarize(q('jvm_memory_bytes_used{job="cfk-jmx", area="heap", kubernetes_namespace="${NS}"} / 1024 / 1024 / 1024'), key="kubernetes_pod_name"))
B["jvm_heap_max_gb"]    = agg(summarize(q('jvm_memory_bytes_max{job="cfk-jmx", area="heap", kubernetes_namespace="${NS}"} / 1024 / 1024 / 1024'), key="kubernetes_pod_name"))
B["gc_time_ms_per_sec"] = agg(summarize(q('sum by (kubernetes_pod_name) (rate(jvm_gc_collection_seconds_sum{job="cfk-jmx", kubernetes_namespace="${NS}"}[1m])) * 1000'), key="kubernetes_pod_name"))
B["bytes_in_mb_per_sec"]  = agg(summarize(q('kafka_server_brokertopicmetrics_oneminuterate{job="cfk-jmx", kubernetes_namespace="${NS}", name="BytesInPerSec", topic=""} / 1024 / 1024'), key="kubernetes_pod_name"))
B["bytes_out_mb_per_sec"] = agg(summarize(q('kafka_server_brokertopicmetrics_oneminuterate{job="cfk-jmx", kubernetes_namespace="${NS}", name="BytesOutPerSec", topic=""} / 1024 / 1024'), key="kubernetes_pod_name"))
B["messages_in_per_sec"]  = agg(summarize(q('kafka_server_brokertopicmetrics_oneminuterate{job="cfk-jmx", kubernetes_namespace="${NS}", name="MessagesInPerSec", topic=""}'), key="kubernetes_pod_name"))
B["under_replicated_partitions"] = agg(summarize(q('kafka_server_replicamanager_value{job="cfk-jmx", kubernetes_namespace="${NS}", name="UnderReplicatedPartitions"}'), key="kubernetes_pod_name"))
B["offline_partitions"]  = agg(summarize(q('kafka_controller_kafkacontroller_value{job="cfk-jmx", kubernetes_namespace="${NS}", name="OfflinePartitionsCount"}'), key="kubernetes_pod_name"))
B["produce_total_p99_ms"] = agg(summarize(q('kafka_network_requestmetrics_99thpercentile{job="cfk-jmx", kubernetes_namespace="${NS}", name="TotalTimeMs", request="Produce"}'), key="kubernetes_pod_name"))
B["produce_local_p99_ms"] = agg(summarize(q('kafka_network_requestmetrics_99thpercentile{job="cfk-jmx", kubernetes_namespace="${NS}", name="LocalTimeMs", request="Produce"}'), key="kubernetes_pod_name"))
B["produce_remote_p99_ms"]= agg(summarize(q('kafka_network_requestmetrics_99thpercentile{job="cfk-jmx", kubernetes_namespace="${NS}", name="RemoteTimeMs", request="Produce"}'), key="kubernetes_pod_name"))
B["produce_queue_p99_ms"] = agg(summarize(q('kafka_network_requestmetrics_99thpercentile{job="cfk-jmx", kubernetes_namespace="${NS}", name="RequestQueueTimeMs", request="Produce"}'), key="kubernetes_pod_name"))
B["request_handler_idle_pct"] = agg(summarize(q('kafka_server_kafkarequesthandlerpool_oneminuterate{job="cfk-jmx", kubernetes_namespace="${NS}", name="RequestHandlerAvgIdlePercent"} * 100'), key="kubernetes_pod_name"))
B["isr_shrinks_per_sec"] = agg(summarize(q('kafka_server_replicamanager_oneminuterate{job="cfk-jmx", kubernetes_namespace="${NS}", name="IsrShrinksPerSec"}'), key="kubernetes_pod_name"))
B["replica_fetcher_max_lag"] = agg(summarize(q('kafka_server_replicafetchermanager_value{job="cfk-jmx", kubernetes_namespace="${NS}", name="MaxLag"}'), key="kubernetes_pod_name"))

# ═══════ PRODUCERS (OMB worker pods, producer clients) ═══════
P = result["producers"] = {}
P["cpu_cores"]        = agg(summarize(q('sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="${NS}", pod=~"omb-worker-ir-sweep-.*", container="worker"}[1m]))')))
P["mem_working_gb"]   = agg(summarize(q('container_memory_working_set_bytes{namespace="${NS}", pod=~"omb-worker-ir-sweep-.*", container="worker"} / 1024 / 1024 / 1024')))
P["jvm_heap_used_gb"] = agg(summarize(q('jvm_memory_bytes_used{area="heap", pod=~"omb-worker-ir-sweep-.*"} / 1024 / 1024 / 1024')))
P["jvm_threads"]      = agg(summarize(q('jvm_threads_threadcount{pod=~"omb-worker-ir-sweep-.*"}')))
P["record_send_rate"] = agg(summarize(q('sum by (pod) (kafka_producer_record_send_rate{pod=~"omb-worker-ir-sweep-.*"})')))
P["request_latency_avg_ms"] = agg(summarize(q('avg by (pod) (kafka_producer_request_latency_avg{pod=~"omb-worker-ir-sweep-.*"})')))
P["request_latency_max_ms"] = agg(summarize(q('max by (pod) (kafka_producer_request_latency_max{pod=~"omb-worker-ir-sweep-.*"})')))
P["batch_size_avg"]   = agg(summarize(q('avg by (pod) (kafka_producer_batch_size_avg{pod=~"omb-worker-ir-sweep-.*"})')))
P["record_error_rate"] = agg(summarize(q('sum by (pod) (kafka_producer_record_error_rate{pod=~"omb-worker-ir-sweep-.*"})')))

# ═══════ CONSUMERS (OMB worker pods, consumer clients) ═══════
C = result["consumers"] = {}
C["records_consumed_rate"] = agg(summarize(q('sum by (pod) (kafka_consumer_records_consumed_rate{pod=~"omb-worker-ir-sweep-.*"})')))
C["bytes_consumed_mb_per_sec"] = agg(summarize(q('sum by (pod) (kafka_consumer_bytes_consumed_rate{pod=~"omb-worker-ir-sweep-.*"}) / 1024 / 1024')))
C["fetch_latency_avg_ms"] = agg(summarize(q('avg by (pod) (kafka_consumer_fetch_latency_avg{pod=~"omb-worker-ir-sweep-.*"})')))
C["fetch_latency_max_ms"] = agg(summarize(q('max by (pod) (kafka_consumer_fetch_latency_max{pod=~"omb-worker-ir-sweep-.*"})')))
C["fetch_size_avg_bytes"] = agg(summarize(q('avg by (pod) (kafka_consumer_fetch_size_avg{pod=~"omb-worker-ir-sweep-.*"})')))
C["records_lag_max"]      = agg(summarize(q('max by (pod) (kafka_consumer_records_lag_max{pod=~"omb-worker-ir-sweep-.*"})')))
C["commit_latency_avg_ms"] = agg(summarize(q('avg by (pod) (kafka_consumer_commit_latency_avg{pod=~"omb-worker-ir-sweep-.*"})')))

# ═══════ NODES (via node-exporter, filtered by discovered host IPs) ═══════
N = result["nodes"] = {}
N["broker_nodes_cpu_pct"] = agg(summarize(q(f'100 - (avg by (instance) (rate(node_cpu_seconds_total{{mode="idle", instance=~"{broker_re}"}}[1m])) * 100)'), key="instance"))
N["broker_nodes_mem_pct"] = agg(summarize(q(f'(1 - (node_memory_MemAvailable_bytes{{instance=~"{broker_re}"}} / node_memory_MemTotal_bytes{{instance=~"{broker_re}"}})) * 100'), key="instance"))
N["broker_nodes_net_rx_mb"] = agg(summarize(q(f'sum by (instance) (rate(node_network_receive_bytes_total{{device!~"lo|veth.*|docker.*", instance=~"{broker_re}"}}[1m])) / 1024 / 1024'), key="instance"))
N["broker_nodes_net_tx_mb"] = agg(summarize(q(f'sum by (instance) (rate(node_network_transmit_bytes_total{{device!~"lo|veth.*|docker.*", instance=~"{broker_re}"}}[1m])) / 1024 / 1024'), key="instance"))
N["omb_nodes_cpu_pct"]    = agg(summarize(q(f'100 - (avg by (instance) (rate(node_cpu_seconds_total{{mode="idle", instance=~"{omb_re}"}}[1m])) * 100)'), key="instance"))
N["omb_nodes_mem_pct"]    = agg(summarize(q(f'(1 - (node_memory_MemAvailable_bytes{{instance=~"{omb_re}"}} / node_memory_MemTotal_bytes{{instance=~"{omb_re}"}})) * 100'), key="instance"))
N["omb_nodes_net_rx_mb"]  = agg(summarize(q(f'sum by (instance) (rate(node_network_receive_bytes_total{{device!~"lo|veth.*|docker.*", instance=~"{omb_re}"}}[1m])) / 1024 / 1024'), key="instance"))
N["omb_nodes_net_tx_mb"]  = agg(summarize(q(f'sum by (instance) (rate(node_network_transmit_bytes_total{{device!~"lo|veth.*|docker.*", instance=~"{omb_re}"}}[1m])) / 1024 / 1024'), key="instance"))

# ═══════ OMB RESULT JSON ═══════
try:
    with open(f"{OUT}/result.json") as f: omb = json.load(f)
    def avg(l): return round(sum(l)/len(l), 2) if l else None
    def maxv(l): return round(max(l), 2) if l else None
    result["omb_result"] = {
        "publishRate_avg": avg(omb.get("publishRate", [])),
        "consumeRate_avg": avg(omb.get("consumeRate", [])),
        "backlog_max": maxv(omb.get("backlog", [])),
        "publishLatency_ms": {k: omb.get(f"aggregatedPublishLatency{k}") for k in ("50pct","95pct","99pct","999pct","9999pct","Max")},
        "endToEndLatency_ms": {k: omb.get(f"aggregatedEndToEndLatency{k}") for k in ("50pct","95pct","99pct","999pct","9999pct","Max")},
    }
except Exception as e:
    result["omb_result"] = {"error": str(e)}

print(json.dumps(result, indent=2, default=str))
PYEOF

# ─── Final summary ───
echo "[$(date +%H:%M:%S)] metrics.json saved → $OUT/metrics.json"
python3 <<SUMEOF
import json
with open("$OUT/metrics.json") as f: d = json.load(f)
w = d.get("window", {})
print(f'\n── Test window: {w.get("start","?")[-14:-6]} → {w.get("end","?")[-14:-6]}  ({w.get("duration_min")} min) ──')
omb = d.get("omb_result", {})
if isinstance(omb, dict) and "publishLatency_ms" in omb:
    p, e = omb["publishLatency_ms"], omb["endToEndLatency_ms"]
    print(f'  publish latency ms:  p50={p.get("50pct"):>6}  p99={p.get("99pct"):>6}  p999={p.get("999pct"):>6}  max={p.get("Max"):>6}')
    print(f'  E2E latency ms:      p50={e.get("50pct"):>6}  p99={e.get("99pct"):>6}  p999={e.get("999pct"):>6}  max={e.get("Max"):>6}')
    print(f'  publishRate: {omb.get("publishRate_avg"):>8} rec/s   consumeRate: {omb.get("consumeRate_avg"):>8} rec/s   backlog_max: {omb.get("backlog_max")}')
print()
for cat in ("brokers_east1","producers","consumers","nodes"):
    print(f'── {cat} ──')
    for k, v in d.get(cat, {}).items():
        if v is None:
            print(f'  {k:30s}  (no data)')
        else:
            print(f'  {k:30s}  avg={v["cluster_avg"]:>10}  max={v["cluster_max"]:>10}  n={v["pod_count"]}')
    print()
SUMEOF
