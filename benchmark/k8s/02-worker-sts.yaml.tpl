apiVersion: v1
kind: Service
metadata:
  name: omb-worker-ir-sweep
  namespace: ${NAMESPACE}
  labels:
    app: omb
    component: worker
    sweep: ir-ab-2026-10-21
spec:
  clusterIP: None
  ports:
    - port: 8080
      name: http
    - port: 8081
      name: stats
    - port: 7778
      name: jmx-metrics
  selector:
    app: omb
    component: worker
    sweep: ir-ab-2026-10-21
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: omb-worker-ir-sweep
  namespace: ${NAMESPACE}
  labels:
    app: omb
    component: worker
    sweep: ir-ab-2026-10-21
spec:
  serviceName: omb-worker-ir-sweep
  replicas: ${OMB_WORKER_REPLICAS}
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: omb
      component: worker
      sweep: ir-ab-2026-10-21
  template:
    metadata:
      labels:
        app: omb
        component: worker
        sweep: ir-ab-2026-10-21
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "7778"
        prometheus.io/path: "/metrics"
    spec:
      nodeSelector:
        cflt-cp-nodeType: omb-client
      tolerations:
        - key: dedicated
          operator: Equal
          value: omb-client
          effect: NoSchedule
      initContainers:
        - name: resolve-driver
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              set -e
              cp /config-template/driver-kafka.yaml /shared/driver-kafka.yaml
              for W in workload-150t-100p-1kb-50mb workload-150t-100p-1kb-100mb workload-150t-100p-1kb-200mb workload-150t-100p-1kb-300mb; do
                cp /config-template/${W}.yaml /shared/${W}.yaml
              done
              PASS=$(grep -oE '[^=]+$' /mnt/sslcerts/jksPassword.txt)
              sed -i "s|KEYSTORE_PASSWORD_PLACEHOLDER|$PASS|g" /shared/driver-kafka.yaml
              grep -c "KEYSTORE_PASSWORD_PLACEHOLDER" /shared/driver-kafka.yaml && echo "ERROR: placeholder still present" && exit 1 || true
              ls -la /shared/
          volumeMounts:
            - name: config-template
              mountPath: /config-template
            - name: shared
              mountPath: /shared
            - name: sslcerts
              mountPath: /mnt/sslcerts
              readOnly: true
        - name: jmx-exporter-downloader
          image: curlimages/curl:8.10.1
          command:
            - sh
            - -c
            - |
              set -e
              curl -sSfL -o /opt/jmx/jmx_prometheus_javaagent.jar \
                https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${JMX_EXPORTER_VERSION}.jar
              ls -la /opt/jmx/
          volumeMounts:
            - name: jmx-agent
              mountPath: /opt/jmx
      containers:
        - name: worker
          image: ${OMB_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c"]
          args:
            - bin/benchmark-worker
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 8081
              name: stats
            - containerPort: 7778
              name: jmx-metrics
          resources:
            requests:
              cpu: "24"
              memory: 48Gi
            limits:
              cpu: "28"
              memory: 56Gi
          env:
            # OMB's bin/benchmark-worker reads HEAP_OPTS if set, otherwise defaults
            # to -Xms4G -Xmx4G which OOM'd with 150p + 300c client instances.
            # 8GB handles our client working set with comfortable margin.
            - name: HEAP_OPTS
              value: "${OMB_WORKER_HEAP}"
            # JAVA_TOOL_OPTIONS gets picked up by every JVM invocation.
            # Used here to inject the JMX exporter agent (which exposes /metrics
            # on :7778 for Prometheus scraping of kafka.producer/consumer MBeans).
            - name: JAVA_TOOL_OPTIONS
              value: "-javaagent:/opt/jmx/jmx_prometheus_javaagent.jar=7778:/opt/jmx-config/kafka-client.yml"
          volumeMounts:
            - name: shared
              mountPath: /opt/omb-config
            - name: sslcerts
              mountPath: /mnt/sslcerts
              readOnly: true
            - name: jmx-agent
              mountPath: /opt/jmx
              readOnly: true
            - name: jmx-config
              mountPath: /opt/jmx-config
              readOnly: true
      volumes:
        - name: config-template
          configMap:
            name: omb-configs-ir-sweep
        - name: shared
          emptyDir: {}
        - name: sslcerts
          secret:
            secretName: kafka-tls
        - name: jmx-agent
          emptyDir: {}
        - name: jmx-config
          configMap:
            name: omb-jmx-exporter-config
