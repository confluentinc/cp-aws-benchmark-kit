# Terraform

AWS primitives for cp-benchmark-kit. All Kubernetes-layer installs (CFK operator, kube-prometheus-stack, nginx-ingress) live in `../bootstrap/` and run after this.

## Layout

```
terraform/
├── remote-state/       # ONE-TIME: S3 state bucket + DynamoDB lock table
├── modules/            # reusable modules
│   ├── vpc/            # VPC + 3 private /22 + 3 public /22 subnets + NAT + IGW + routes
│   ├── eks-cluster/    # EKS control plane + OIDC + core addons (vpc-cni, coredns, kube-proxy, ebs-csi)
│   ├── eks-nodegroup/  # reusable: ng-base, ng-brokers, ng-omb-clients
│   ├── route53-private/# private hosted zone + VPC association (local + optional peer)
│   ├── iam-irsa/       # AWS LB Controller role (needs policies/aws-lb-controller.json)
│   └── tgw-peering/    # OPTIONAL — cross-region TGW for cluster-link path
└── envs/
    ├── east1/          # per-region root module: calls modules with .env-sourced values
    └── east2/          # symmetric
```

## One-time setup (per AWS account)

```bash
# 1. Download AWS LB Controller IAM policy (see modules/iam-irsa/policies/README.md)
cd modules/iam-irsa/policies
curl -o aws-lb-controller.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# 2. Bootstrap remote state bucket
cd ../../../remote-state
terraform init
terraform apply -var aws_profile=my-profile -var bucket_name=cp-benchmark-kit-tfstate-$(aws sts get-caller-identity --query Account --output text --profile my-profile)
# Note the output bucket_name + table_name — paste into envs/east{1,2}/backend.tf
```

## Per-region apply

```bash
cd envs/east1
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your region/cluster/CIDR/zone values
terraform init
terraform apply
```

Then do the same for `envs/east2`.

## Cross-region Route53 association (optional, for cluster-link)

After both regions are up, re-apply east1 with east2's VPC ID (and vice versa) to associate each region's private hosted zone with the OTHER region's VPC. This lets brokers in east1 resolve east2's domain names (`cl.cp.east2.example.internal`) during cluster-link bootstrap.

```bash
# From east2 output:
EAST2_VPC_ID=$(cd envs/east2 && terraform output -raw vpc_id)

# Re-apply east1 with peer VPC
cd envs/east1
terraform apply -var "peer_vpc_id=${EAST2_VPC_ID}" -var "peer_vpc_region=us-east-2"
# (Add peer_vpc_id / peer_vpc_region variables to envs/east1/variables.tf first;
#  wire them through to module.route53.peer_vpc_id in main.tf.)
```

Alternatively use existing your organization's networking infrastructure (TGW, VPC peering already managed by platform team).

## Pulling outputs into .env

```bash
# From repo root
make tf-output-to-env
```

This runs a helper script (`scripts/tf-output-to-env.sh`) that reads `terraform output -json` from both envs and updates `PRIVATE_SUBNETS_REGION{1,2}`, `ROUTE53_ZONE_ID_REGION{1,2}`, etc. in `.env`.

## Validation (without applying)

```bash
cd envs/east1
terraform init -backend=false  # skip backend for pure validation
terraform validate
terraform plan                   # will fail on real AWS resources if creds aren't valid, but syntax is checked
```

## Destroying

```bash
# Always destroy brokers + benchmark workloads FIRST (kubectl delete).
# Then:
cd envs/east1 && terraform destroy
cd envs/east2 && terraform destroy
# Finally remote-state (optional — can keep bucket for future redeploys):
cd remote-state && terraform destroy
```
