apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: __CLUSTER_NAME__
  region: __REGION__
  version: "__EKS_VERSION__"

managedNodeGroups:
  - name: ng-ingress-xl
    instanceType: __INGRESS_INSTANCE__       # c7gn.2xlarge recommended (8 vCPU, 50 Gbps)
    amiFamily: AmazonLinux2023
    minSize: __INGRESS_NODE_COUNT__
    maxSize: __INGRESS_NODE_COUNT__
    desiredCapacity: __INGRESS_NODE_COUNT__
    volumeSize: 50
    subnets: __SUBNET_LIST_YAML__
    labels:
      cflt-cp-nodeType: ingress-nginx-xl
    taints:
      - key: dedicated
        value: ingress-nginx
        effect: NoSchedule
    tags:
      purpose: nginx-ingress-sni
