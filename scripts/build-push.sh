#!/bin/bash
# Build the cargo-tracker Docker image and push it to AWS ECR or Docker Hub.
# Run from the repository root:  ./scripts/build-push.sh
set -e
set -o pipefail

cd "$(dirname "$0")/.."

PROJECT_NAME="cargo-tracker"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== Cargo Tracker - build and push ==="
echo "Select registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -r -p "Enter choice [1-2]: " REGISTRY_CHOICE

read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(echo "${IMAGE_TAG:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

case "$REGISTRY_CHOICE" in
  1)
    command -v aws >/dev/null 2>&1 || { echo "ERROR: aws cli is required"; exit 1; }
    read -r -p "Enter AWS region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    read -r -p "Enter AWS account ID (leave empty to auto-detect): " AWS_ACCOUNT_ID
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    read -r -p "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

    echo "Logging in to ECR ${REGISTRY_URL} ..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

    echo "Ensuring ECR repository ${ECR_REPO} exists ..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
      aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    ;;
  2)
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub password / access token: " DOCKER_PASSWORD
    echo
    read -r -p "Enter repository name [$IMAGE_NAME]: " DOCKER_REPO
    DOCKER_REPO=${DOCKER_REPO:-$IMAGE_NAME}
    DOCKER_USERNAME=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${DOCKER_REPO}:${IMAGE_TAG}"

    echo "Logging in to Docker Hub ..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    ;;
  *)
    echo "ERROR: invalid choice"; exit 1
    ;;
esac

echo "Building image ${FULL_IMAGE_NAME} ..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image ${FULL_IMAGE_NAME} ..."
docker push "$FULL_IMAGE_NAME"

echo "-------------------------------------------------------------"
echo "Image pushed successfully: ${FULL_IMAGE_NAME}"
echo "Use this URI with scripts/deploy-image.sh"
echo "-------------------------------------------------------------"
