# OpenTelemetry Collector (contrib build) for the latency-probe OTel pilot.
# Receives OTLP from Spring Boot pods carrying the OTel Java agent,
# re-exposes as Prometheus scrape endpoint on :8889. One replica is plenty
# for a 2-pod pilot — scale out later if the full fleet migrates to this path.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: ${NAMESPACE}
  labels:
    app: otel-collector
spec:
  replicas: 2
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
      annotations:
        # Picked up by the existing kube-prometheus-stack k8s_sd scrape job
        # (cfk-prometheus-grafana-cflt-east1/kube-prometheus-stack-values.yaml:175-217).
        # Monitoring namespace scrape job uses the same annotation pattern.
        prometheus.io/scrape: "true"
        prometheus.io/port: "8889"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:0.111.0
          imagePullPolicy: IfNotPresent
          args:
            - --config=/etc/otelcol-contrib/config.yaml
          ports:
            - name: otlp-grpc
              containerPort: 4317
            - name: otlp-http
              containerPort: 4318
            - name: metrics
              containerPort: 8889
            - name: health
              containerPort: 13133
          volumeMounts:
            - name: config
              mountPath: /etc/otelcol-contrib
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "4"
              memory: "4Gi"
          livenessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 13133
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
            items:
              - key: config.yaml
                path: config.yaml
