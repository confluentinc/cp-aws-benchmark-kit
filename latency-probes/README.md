# latency-probes/ (OPTIONAL)

Spring Boot + OTel-instrumented producer / consumer apps for organic client-side latency measurement. **Not required** for the OMB benchmark — OMB already captures publish and E2E latency via its own HdrHistograms.

Use these probes when:
- You want continuous (not just benchmark-window) latency visibility
- You want distributed tracing (via OTel + Tempo/Jaeger) to attribute latency to specific stages (produce send, broker ack, mirror hop, consumer poll, process)
- You want to validate OMB numbers against an independent measurement path

## What they do

- **Producer**: writes correlation headers + timestamp to a dedicated latency-probe topic; paces to a target TPS
- **Consumer**: reads from the probe topic; computes `now - sendTimestamp`; exposes histograms via `/actuator/prometheus` (also sends OTel spans)

## Files

Original source: `../../springboot/` (in the pre-consolidation repo). To use:

1. Copy source into `latency-probes/producer/` and `latency-probes/consumer/`
2. Template Deployment YAMLs (`k8s/pilot-producer.yaml.tpl`, `k8s/pilot-consumer.yaml.tpl`) with bootstrap endpoint + topic name
3. Build images, push to ECR
4. `kubectl apply` the templated manifests

Metrics exposed:
- `latency_probe_messages_sent_total` (counter)
- `latency_probe_e2e_delay_seconds` (histogram)
- `latency_probe_e2e_delay_logappend_seconds` (histogram — uses broker's log-append timestamp instead of client send time)

Grafana dashboard: `observability/grafana-dashboards/latency-probe-otel-dashboard-configmap.yml` is already included and auto-provisioned by the sidecar.

## Status

Present as a stub/placeholder in this consolidation. The original Spring Boot source + K8s manifests live in the pre-consolidation repo at `../../springboot/` and can be migrated when needed.
