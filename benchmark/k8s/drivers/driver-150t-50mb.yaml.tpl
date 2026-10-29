apiVersion: batch/v1
kind: Job
metadata:
  name: omb-driver-150t-50mb
  namespace: ${NAMESPACE}
  labels:
    app: omb
    component: driver
    sweep: ir-ab-2026-10-23
    workload: 150t-100p-1kb-50mb
    throughput-mbs: "50"
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: omb
        component: driver
        sweep: ir-ab-2026-10-23
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/arch: arm64
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
              cp /config-template/workload-150t-100p-1kb-50mb.yaml /shared/workload.yaml
              PASS=$(grep -oE '[^=]+$' /mnt/sslcerts/jksPassword.txt)
              sed -i "s|KEYSTORE_PASSWORD_PLACEHOLDER|$PASS|g" /shared/driver-kafka.yaml
          volumeMounts:
            - {name: config-template, mountPath: /config-template}
            - {name: shared, mountPath: /shared}
            - {name: sslcerts, mountPath: /mnt/sslcerts, readOnly: true}
      containers:
        - name: driver
          image: ${OMB_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c"]
          args:
            - |
              set -e
              cd /benchmark
              echo "=== workload: ==="
              head -20 /shared/workload.yaml
              echo "=== starting benchmark at $(date -u) ==="
              bin/benchmark \
                --drivers /shared/driver-kafka.yaml \
                --workers http://omb-worker-ir-sweep-0.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-1.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-2.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-3.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080 \
                --output /shared/result-150t-50mb.json \
                /shared/workload.yaml
              echo "=== BENCHMARK DONE at $(date -u) ==="
              echo "=== FULL_RESULT_JSON_START ==="
              cat /shared/result-150t-50mb.json
              echo ""
              echo "=== FULL_RESULT_JSON_END ==="
          resources:
            requests: {cpu: "2", memory: 8Gi}
            limits:   {cpu: "4", memory: 16Gi}
          env:
            - {name: JVM_MEM, value: "-Xms4G -Xmx12g"}
          volumeMounts:
            - {name: shared, mountPath: /shared}
            - {name: sslcerts, mountPath: /mnt/sslcerts, readOnly: true}
      volumes:
        - {name: config-template, configMap: {name: omb-configs-ir-sweep}}
        - {name: shared, emptyDir: {}}
        - {name: sslcerts, secret: {secretName: kafka-tls}}
