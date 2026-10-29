# Helm values for nginx-ingress zone A (us-east-1a).
# Install:
#   helm --kube-context <your-context> upgrade --install nginx-zone-a \
#     ingress-nginx/ingress-nginx -n ingress-nginx --version 4.11.3 \
#     -f values-zone-a.yaml

controller:
  # Each AZ gets its own ingressClass + controllerClass so the 3 nginx controllers
  # don't fight over the same Ingress objects. Each Ingress is annotated with
  # its target class → only the matching controller processes it.
  ingressClassResource:
    name: nginx-zone-a
    enabled: true
    default: false
    controllerValue: "k8s.io/nginx-zone-a"
  ingressClass: nginx-zone-a
  electionID: ingress-controller-leader-zone-a

  # One replica per AZ. Pinned to a node in us-east-1a via nodeSelector + ng-ingress taint.
  replicaCount: 1

  nodeSelector:
    cflt-cp-nodeType: ingress-nginx-xl   # expects ng-ingress-xl nodegroup   # 2026-10-24: upgraded m7g.large → c7gn.2xlarge; original 1500m limit saturated at 150 MB/s
    topology.kubernetes.io/zone: us-east-1a

  tolerations:
    - key: dedicated
      operator: Equal
      value: ingress-nginx
      effect: NoSchedule

  # Mandatory for Confluent static-host-based routing: nginx must forward raw TLS
  # bytes to the broker rather than terminating TLS itself. SNI header is the
  # routing key.
  extraArgs:
    enable-ssl-passthrough: "true"

  # SSL passthrough listens on 443 by default. HTTP :80 is unused — brokers don't
  # speak HTTP — but ingress-nginx insists on binding it, so leave it.
  containerPort:
    http: 80
    https: 443

  config:
    # Longer connection timeout — producer stays idle on a connection between batches
    # and we don't want nginx reaping sockets mid-benchmark.
    proxy-connect-timeout: "30"
    proxy-read-timeout: "600"
    proxy-send-timeout: "600"

  resources:
    requests:
      cpu: 2000m
      memory: 1Gi
    limits:
      cpu: 7000m   # 7 of 8 vCPU on c7gn.2xlarge; leaves 1 for OS + kubelet
      memory: 4Gi

  service:
    enabled: true
    type: LoadBalancer
    externalTrafficPolicy: Local   # preserves client source IP; AZ-local hop
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: external
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      # Pin NLB to us-east-1a /22 subnet
      service.beta.kubernetes.io/aws-load-balancer-subnets: "__SUBNET_AZ_A__"
    ports:
      http: 80
      https: 443
    targetPorts:
      http: http
      https: https

  # Scrape by existing kube-prometheus-stack via annotations (reuses the same
  # pattern as kafka-client-jmx — see docs/architecture.md 1.5)
  metrics:
    enabled: true
    service:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "10254"
