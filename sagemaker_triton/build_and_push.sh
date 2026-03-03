#!/bin/bash

# Accept DOCKER_IMAGE as a parameter, if not provided use a default value
DOCKER_IMAGE=${1:-"sagemaker-endpoint/whisper-triton-byoc:latest"}

# Optional target region override (2nd arg). Falls back to REGION env and then aws config.
TARGET_REGION=${2:-${REGION:-$(aws configure get region)}}

if [ -z "${TARGET_REGION}" ]; then
    echo "Error: region is not set. Pass it as the second argument or configure aws region."
    exit 1
fi

# Extract REPO_NAMESPACE and TAG from DOCKER_IMAGE
REPO_NAMESPACE=$(echo $DOCKER_IMAGE | cut -d':' -f1)
TAG=$(echo $DOCKER_IMAGE | cut -d':' -f2)

# Get the ACCOUNT from current AWS identity
ACCOUNT=${ACCOUNT:-$(aws sts get-caller-identity --query Account --output text)}
REGION=${TARGET_REGION}

REPO_NAME="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAMESPACE}:${TAG}"
echo ${REPO_NAME}

# If the repository doesn't exist in ECR, create it.
aws ecr describe-repositories --repository-names "${REPO_NAMESPACE}" > /dev/null 2>&1
if [ $? -ne 0 ]
then
    echo "create repository:" "${REPO_NAMESPACE}"
    aws ecr create-repository --repository-name "${REPO_NAMESPACE}" > /dev/null
fi

# Log into Docker
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Build docker
docker build . -f Dockerfile.server -t ${DOCKER_IMAGE}

# Push it
docker tag ${DOCKER_IMAGE} ${REPO_NAME}
docker push ${REPO_NAME}
