# OpenTelemetry Collector config for the latency-probe OTel pilot (east1).
# Receives OTLP (gRPC :4317, HTTP :4318) from pods running the OTel Java agent,
# re-exports as Prometheus scrape endpoint on :8889 — the existing kube-prometheus-stack
# k8s_sd scrape job discovers it via prometheus.io/scrape annotation on the pod.
#
# resource_to_telemetry_conversion.enabled: true promotes OTel resource attributes
# (set via OTEL_RESOURCE_ATTRIBUTES=source=otel,...) to Prometheus labels, so the
# `source="otel"` label makes OTel-sourced metrics distinguishable from the parallel
# Actuator-scraped series.
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: ${NAMESPACE}
  labels:
    app: otel-collector
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 5s
        send_batch_size: 1024
      memory_limiter:
        check_interval: 1s
        limit_percentage: 85
        spike_limit_percentage: 20
      # Drop high-cardinality per-pod/per-host resource attributes before they
      # become Prometheus labels. Keeps only the aggregating labels we actually
      # use on dashboards: source, region, role, direction, topic, scale,
      # service.name. Everything else is noise that explodes TSDB series count.
      resource:
        attributes:
          - { action: delete, key: host.arch }
          - { action: delete, key: host.name }
          - { action: delete, key: os.type }
          - { action: delete, key: os.version }
          - { action: delete, key: os.description }
          - { action: delete, key: process.command_args }
          - { action: delete, key: process.executable.path }
          - { action: delete, key: process.pid }
          - { action: delete, key: process.runtime.description }
          - { action: delete, key: process.runtime.name }
          - { action: delete, key: process.runtime.version }
          - { action: delete, key: telemetry.distro.name }
          - { action: delete, key: telemetry.distro.version }
          - { action: delete, key: telemetry.sdk.language }
          - { action: delete, key: telemetry.sdk.name }
          - { action: delete, key: telemetry.sdk.version }
          # service.instance.id intentionally KEPT — Prometheus exporter uses it
          # to form unique series names; dropping it causes all metrics to be
          # silently discarded by the exporter.
          - { action: delete, key: service.version }

    exporters:
      prometheus:
        endpoint: 0.0.0.0:8889
        send_timestamps: true
        resource_to_telemetry_conversion:
          enabled: true
        # 2026-10-19: enable OpenMetrics format so Base2 Exponential Histograms
        # from the OTel SDK are preserved as Prometheus native histograms
        # instead of being downgraded to explicit buckets on export.
        enable_open_metrics: true
      # 2026-10-19: push traces to Tempo (grafana/tempo helm release in the
      # monitoring namespace). Insecure/TLS-off is fine inside the cluster.
      otlp/tempo:
        endpoint: tempo.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      # 2026-10-19: also fan traces to Jaeger all-in-one so we can confirm
      # whether Jaeger's UI reveals detail Tempo's view doesn't (expected:
      # no, since the span data is identical — but worth proving).
      otlp/jaeger:
        endpoint: jaeger.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      debug:
        verbosity: basic
        sampling_initial: 2
        sampling_thereafter: 500

    extensions:
      health_check:
        endpoint: 0.0.0.0:13133

    service:
      extensions: [health_check]
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, resource, batch]
          exporters: [prometheus, debug]
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp/tempo, otlp/jaeger]
      telemetry:
        logs:
          level: info
