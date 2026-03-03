#!/bin/bash
set -euo pipefail

# Accept DOCKER_IMAGE as a parameter, if not provided use a default value
DOCKER_IMAGE=${1:-"sagemaker-endpoint/whisper-triton-byoc:latest"}

# Optional target region override (2nd arg). Falls back to REGION env and then aws config.
TARGET_REGION=${2:-${REGION:-$(aws configure get region)}}

# Optional local BuildKit cache directory override (3rd arg).
# You can also set DOCKER_BUILD_CACHE_DIR env var.
BUILD_CACHE_DIR=${3:-${DOCKER_BUILD_CACHE_DIR:-}}

if [ -z "${TARGET_REGION}" ]; then
    echo "Error: region is not set. Pass it as the second argument or configure aws region."
    exit 1
fi

# Extract REPO_NAMESPACE and TAG from DOCKER_IMAGE
REPO_NAMESPACE=$(echo "$DOCKER_IMAGE" | cut -d':' -f1)
TAG=$(echo "$DOCKER_IMAGE" | cut -d':' -f2)

# Get the ACCOUNT from current AWS identity
ACCOUNT=${ACCOUNT:-$(aws sts get-caller-identity --query Account --output text)}
REGION=${TARGET_REGION}

REPO_NAME="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAMESPACE}:${TAG}"
echo "Target ECR image: ${REPO_NAME}"

# If the repository doesn't exist in ECR, create it.
if ! aws ecr describe-repositories --region "${REGION}" --repository-names "${REPO_NAMESPACE}" > /dev/null 2>&1; then
    echo "create repository: ${REPO_NAMESPACE}"
    aws ecr create-repository --region "${REGION}" --repository-name "${REPO_NAMESPACE}" > /dev/null
fi

# Log into Docker
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

# Build docker
if [ -n "${BUILD_CACHE_DIR}" ]; then
    mkdir -p "${BUILD_CACHE_DIR}"
    echo "Using buildx local cache dir: ${BUILD_CACHE_DIR}"
    docker buildx build \
      --load \
      --cache-from "type=local,src=${BUILD_CACHE_DIR}" \
      --cache-to "type=local,dest=${BUILD_CACHE_DIR},mode=max" \
      -f Dockerfile.server \
      -t "${DOCKER_IMAGE}" \
      .
else
    docker build . -f Dockerfile.server -t "${DOCKER_IMAGE}"
fi

# Push it
docker tag "${DOCKER_IMAGE}" "${REPO_NAME}"
docker push "${REPO_NAME}"
