# Helm values for nginx-ingress zone C (us-east-1c).
# Install:
#   helm --kube-context <your-context> upgrade --install nginx-zone-c \
#     ingress-nginx/ingress-nginx -n ingress-nginx --version 4.11.3 \
#     -f values-zone-c.yaml

controller:
  ingressClassResource:
    name: nginx-zone-c
    enabled: true
    default: false
    controllerValue: "k8s.io/nginx-zone-c"
  ingressClass: nginx-zone-c
  electionID: ingress-controller-leader-zone-c

  replicaCount: 1

  nodeSelector:
    cflt-cp-nodeType: ingress-nginx-xl   # expects ng-ingress-xl nodegroup   # 2026-10-24: upgraded m7g.large → c7gn.2xlarge; original 1500m limit saturated at 150 MB/s
    topology.kubernetes.io/zone: us-east-1c

  tolerations:
    - key: dedicated
      operator: Equal
      value: ingress-nginx
      effect: NoSchedule

  extraArgs:
    enable-ssl-passthrough: "true"

  containerPort:
    http: 80
    https: 443

  config:
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
    externalTrafficPolicy: Local
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: external
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      service.beta.kubernetes.io/aws-load-balancer-subnets: "__SUBNET_AZ_C__"
    ports:
      http: 80
      https: 443
    targetPorts:
      http: http
      https: https

  metrics:
    enabled: true
    service:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "10254"
