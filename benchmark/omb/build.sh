#!/usr/bin/env bash
# Build + push the forked OMB image.
#
# Prerequisite: the openmessaging-benchmark/ fork source tree must be present
# alongside this script (committed as submodule or copied manually). The fork
# adds `topicNames: [...]` field support to the workload YAML, allowing OMB to
# use pre-created topics instead of calling AdminClient.createTopics() which
# times out at 150+ topics.
#
# Pushes to the ECR URI defined in .env as OMB_IMAGE.

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/.env"

# The fork source should live at ${REPO_ROOT}/benchmark/omb/openmessaging-benchmark/
# (as a git submodule or copy of the upstream openmessaging-benchmark repo
# with the topicNames patch applied).
FORK_SRC="${OMB_FORK_SRC:-$REPO_ROOT/benchmark/omb/openmessaging-benchmark}"

if [[ ! -d "$FORK_SRC" ]]; then
  cat <<EOF
ERROR: OMB fork source tree not found at $FORK_SRC

To get the OMB source, clone upstream OpenMessaging Benchmark:

  cd $(dirname "$FORK_SRC")
  git clone https://github.com/openmessaging/openmessaging-benchmark.git
  cd ../..
  make benchmark-build-image     # or bash benchmark/omb/build.sh

For scale testing (150+ topics), see fork-notes.md — upstream needs a small
patch to skip createTopics when topics are pre-created.

Alternative: point OMB_FORK_SRC at an existing checkout:
  OMB_FORK_SRC=/path/to/your/omb-checkout bash build.sh

Alternative: skip the build and set OMB_IMAGE in .env to a prebuilt image.
EOF
  exit 1
fi

echo "[$(date +%H:%M:%S)] Building $OMB_IMAGE from $FORK_SRC"

# ECR login
ECR_REGISTRY=$(echo "$OMB_IMAGE" | cut -d/ -f1)
aws ecr get-login-password --region "$REGION1" --profile "$AWS_PROFILE" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Ensure the ECR repository exists
REPO_NAME=$(echo "$OMB_IMAGE" | sed "s|${ECR_REGISTRY}/||; s|:.*||")
aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION1" --profile "$AWS_PROFILE" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION1" --profile "$AWS_PROFILE"

cd "$FORK_SRC"
docker buildx build \
  --platform linux/arm64 \
  --tag "$OMB_IMAGE" \
  --file docker/Dockerfile \
  --push \
  .

echo "✓ Built + pushed $OMB_IMAGE"
