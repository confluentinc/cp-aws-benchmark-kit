apiVersion: batch/v1
kind: Job
metadata:
  name: omb-driver-150t-150mb
  namespace: ${NAMESPACE}
  labels: {app: omb, component: driver, sweep: ir-ab-2026-10-23, throughput-mbs: "150"}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {kubernetes.io/arch: arm64}
      tolerations: [{key: dedicated, operator: Equal, value: omb-client, effect: NoSchedule}]
      initContainers:
        - name: resolve-driver
          image: busybox:1.36
          command: ["sh","-c"]
          args:
            - |
              set -e
              cp /ct/driver-kafka.yaml /sh/driver-kafka.yaml
              cp /ct/workload-150t-100p-1kb-150mb.yaml /sh/workload.yaml
              PASS=$(grep -oE '[^=]+$' /mnt/sslcerts/jksPassword.txt)
              sed -i "s|KEYSTORE_PASSWORD_PLACEHOLDER|$PASS|g" /sh/driver-kafka.yaml
          volumeMounts:
            - {name: ct, mountPath: /ct}
            - {name: sh, mountPath: /sh}
            - {name: sslcerts, mountPath: /mnt/sslcerts, readOnly: true}
      containers:
        - name: driver
          image: ${OMB_IMAGE}
          command: ["sh","-c"]
          args:
            - |
              set -e
              cd /benchmark
              echo "=== workload: ==="
              head -20 /sh/workload.yaml
              echo "=== starting benchmark at $(date -u) ==="
              bin/benchmark --drivers /sh/driver-kafka.yaml \
                --workers http://omb-worker-ir-sweep-0.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-1.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-2.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080,http://omb-worker-ir-sweep-3.omb-worker-ir-sweep.${NAMESPACE}.svc.cluster.local:8080 \
                --output /sh/result.json /sh/workload.yaml
              echo "=== BENCHMARK DONE at $(date -u) ==="
              echo "=== FULL_RESULT_JSON_START ==="
              cat /sh/result.json
              echo ""
              echo "=== FULL_RESULT_JSON_END ==="
          resources: {requests: {cpu: "2", memory: 8Gi}, limits: {cpu: "4", memory: 16Gi}}
          env: [{name: JVM_MEM, value: "-Xms4G -Xmx12g"}]
          volumeMounts:
            - {name: sh, mountPath: /sh}
            - {name: sslcerts, mountPath: /mnt/sslcerts, readOnly: true}
      volumes:
        - {name: ct, configMap: {name: omb-configs-ir-sweep}}
        - {name: sh, emptyDir: {}}
        - {name: sslcerts, secret: {secretName: kafka-tls}}
