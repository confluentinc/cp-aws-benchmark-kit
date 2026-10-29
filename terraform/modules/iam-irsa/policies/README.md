# IAM policy JSONs

Download the current AWS Load Balancer Controller IAM policy from the upstream repo:

```bash
curl -o aws-lb-controller.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

This file is required by `terraform/modules/iam-irsa/main.tf` (referenced via `file("${path.module}/policies/aws-lb-controller.json")`).

The policy is ~250 lines of JSON covering NLB creation/management, target group ops, and tag read/write. It's maintained by the AWS LB Controller project and may change between releases — pin to a specific release tag if you need stability:

```bash
# Pin to v2.9.0 for example
curl -o aws-lb-controller.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.0/docs/install/iam_policy.json
```

Verify the file is present before running `terraform apply`:
```bash
test -s aws-lb-controller.json || echo "MISSING — download it first"
```
