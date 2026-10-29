# cp-benchmark-kit — top-level Makefile
# All targets read .env (user copies from .env.example first).
# Targets delegate to bootstrap/, benchmark/scripts/, or terraform/envs/ scripts.

SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

ENV_FILE := .env

# Fail fast if .env is missing (except for `help` and `init`)
ifneq ($(filter-out help init,$(MAKECMDGOALS)),)
  ifeq (,$(wildcard $(ENV_FILE)))
    $(error $(ENV_FILE) not found. Run: cp .env.example .env  and edit it.)
  endif
  include $(ENV_FILE)
  export
endif

# ============================================================================
# Help
# ============================================================================
.PHONY: help
help: ## Show this help
	@echo "cp-benchmark-kit — targets (grouped by phase):"
	@echo ""
	@echo "  Setup:"
	@grep -E '^(init|check-prereqs):.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Infra (Terraform):"
	@grep -E '^tf-.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Bootstrap (K8s installs):"
	@grep -E '^bootstrap.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Confluent Platform:"
	@grep -E '^deploy-cp.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Observability:"
	@grep -E '^deploy-obs.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Client-path topology (pick one):"
	@grep -E '^deploy-topology-.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Benchmark:"
	@grep -E '^benchmark-.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "  Teardown:"
	@grep -E '^teardown-.*:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "    make %-30s %s\n", $$1, $$2}'

.PHONY: init
init: ## Copy .env.example → .env (one-time)
	@test -f $(ENV_FILE) && { echo "$(ENV_FILE) already exists; delete it first to re-init"; exit 1; } || true
	cp .env.example $(ENV_FILE)
	@echo "Created $(ENV_FILE). Open it and fill in values, then run: make check-prereqs"

.PHONY: check-prereqs
check-prereqs: ## Verify CLI tools + AWS creds + .env completeness
	@for t in aws kubectl helm eksctl terraform jq python3 envsubst; do \
	  command -v $$t >/dev/null || { echo "✗ MISSING tool: $$t"; exit 1; }; \
	done
	@aws sts get-caller-identity --profile $$AWS_PROFILE >/dev/null \
	  || { echo "✗ AWS credentials failing for profile $$AWS_PROFILE"; exit 1; }
	@bash scripts/check-env.sh

# ============================================================================
# Infra (Terraform)
# ============================================================================
.PHONY: tf-remote-state-init
tf-remote-state-init: ## ONE-TIME: bootstrap S3 state bucket + lock table + auto-wire envs/*/backend.tf
	bash scripts/tf-remote-state-init.sh

.PHONY: tf-apply-east1
tf-apply-east1: ## Terraform apply east1 (VPC, EKS, nodegroups, Route53, IAM)
	cd terraform/envs/east1 && terraform init && terraform apply -auto-approve

.PHONY: tf-apply-east2
tf-apply-east2: ## Terraform apply east2
	cd terraform/envs/east2 && terraform init && terraform apply -auto-approve

.PHONY: tf-output-to-env
tf-output-to-env: ## Pull TF outputs (subnet IDs, zone IDs) back into .env
	@bash scripts/tf-output-to-env.sh

# ============================================================================
# K8s bootstrap (post-Terraform)
# ============================================================================
.PHONY: bootstrap-east1
bootstrap-east1: ## Install AWS LB Controller + EBS CSI + CFK operator + monitoring + mTLS certs on east1
	bash bootstrap/00-kubeconfig.sh east1
	bash bootstrap/01-core-addons.sh east1
	bash bootstrap/02-cfk-operator.sh east1
	bash bootstrap/03-monitoring.sh east1
	bash bootstrap/04-mtls-certs.sh east1

.PHONY: bootstrap-east2
bootstrap-east2: ## Same, for east2
	bash bootstrap/00-kubeconfig.sh east2
	bash bootstrap/01-core-addons.sh east2
	bash bootstrap/02-cfk-operator.sh east2
	bash bootstrap/03-monitoring.sh east2
	bash bootstrap/04-mtls-certs.sh east2

# ============================================================================
# Confluent Platform (Kustomize)
# ============================================================================
.PHONY: set-license
set-license: ## Apply Confluent license Secret in both regions. Usage: make set-license LICENSE_FILE=/path/to/license.key
	bash scripts/set-license.sh $(LICENSE_FILE)

.PHONY: deploy-cp-east1
deploy-cp-east1: ## render overlays from .env + kubectl apply confluent + cluster-link
	bash scripts/render-overlays.sh east1
	kubectl --context $$KUBECTL_CONTEXT_REGION1 apply -k confluent/overlays/east1
	kubectl --context $$KUBECTL_CONTEXT_REGION1 apply -k cluster-link/overlays/east1

.PHONY: deploy-cp-east2
deploy-cp-east2: ## Same for east2
	bash scripts/render-overlays.sh east2
	kubectl --context $$KUBECTL_CONTEXT_REGION2 apply -k confluent/overlays/east2
	kubectl --context $$KUBECTL_CONTEXT_REGION2 apply -k cluster-link/overlays/east2

# ============================================================================
# Observability
# ============================================================================
.PHONY: deploy-observability-east1
deploy-observability-east1: ## kube-prometheus-stack + OTel + Tempo + Jaeger + dashboards
	bash observability/install.sh east1

.PHONY: deploy-observability-east2
deploy-observability-east2:
	bash observability/install.sh east2

# ============================================================================
# Client-path topology (pick ONE per region)
# ============================================================================
.PHONY: deploy-topology-a-east1
deploy-topology-a-east1: ## 15 per-broker NLBs on the CLUSTERLINK listener; applies Kustomize overlay + Route53 CNAMEs
	bash client-path/topology-a-nlb-per-pod/install.sh east1

.PHONY: deploy-topology-a-east2
deploy-topology-a-east2:
	bash client-path/topology-a-nlb-per-pod/install.sh east2

.PHONY: deploy-topology-b-east1
deploy-topology-b-east1: ## 3 shared NLBs + nginx-ingress (SSL passthrough, SNI-routed) on EXTERNAL listener
	bash client-path/topology-b-nginx-ingress/install.sh east1

.PHONY: deploy-topology-b-east2
deploy-topology-b-east2:
	bash client-path/topology-b-nginx-ingress/install.sh east2

# ============================================================================
# Benchmark (OMB)
# ============================================================================
.PHONY: benchmark-build-image
benchmark-build-image: ## Build + push forked OMB image (one-time; or when fork changes)
	bash benchmark/omb/build.sh

.PHONY: benchmark-pre-create-topics
benchmark-pre-create-topics: ## Pre-create BENCHMARK_TOPIC_COUNT topics (idempotent)
	bash benchmark/scripts/pre-create-topics.sh

.PHONY: benchmark-recreate-topics
benchmark-recreate-topics: ## Delete + recreate topics (clean baseline between runs)
	bash benchmark/scripts/recreate-topics.sh

.PHONY: benchmark-ir-ab
benchmark-ir-ab: ## Full IR OFF vs IR ON sweep at 4 throughputs × 2 worker counts
	bash benchmark/scripts/run-sweep.sh ir-ab

.PHONY: benchmark-topology-ab
benchmark-topology-ab: ## Topology A vs B comparison at IR ON (requires both topologies configured)
	bash benchmark/scripts/run-sweep.sh topology-ab

.PHONY: benchmark-report
benchmark-report: ## Render perf-story.md from benchmark/results/
	python3 benchmark/scripts/compare-runs.py --output benchmark/results/perf-story.md

# ============================================================================
# Teardown (destructive — asks for confirmation inside each script)
# ============================================================================
.PHONY: teardown-benchmark
teardown-benchmark: ## Delete OMB STS, driver jobs, ingress nodegroup
	bash benchmark/scripts/teardown.sh

.PHONY: teardown-cp-east1
teardown-cp-east1: ## kubectl delete -k confluent/overlays/east1 + cluster-link
	kubectl --context $$KUBECTL_CONTEXT_REGION1 delete -k cluster-link/overlays/east1 --ignore-not-found
	kubectl --context $$KUBECTL_CONTEXT_REGION1 delete -k confluent/overlays/east1 --ignore-not-found

.PHONY: teardown-cp-east2
teardown-cp-east2:
	kubectl --context $$KUBECTL_CONTEXT_REGION2 delete -k cluster-link/overlays/east2 --ignore-not-found
	kubectl --context $$KUBECTL_CONTEXT_REGION2 delete -k confluent/overlays/east2 --ignore-not-found

.PHONY: tf-destroy-east1
tf-destroy-east1: ## Terraform destroy east1 (irreversible — asks for approval)
	cd terraform/envs/east1 && terraform destroy

.PHONY: tf-destroy-east2
tf-destroy-east2:
	cd terraform/envs/east2 && terraform destroy
