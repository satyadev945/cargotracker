#!/bin/bash
# Build and push the cargo-tracker Docker image to Azure ACR or Docker Hub.
# Run from the repository root:  ./scripts/build-push.sh
set -e
set -o pipefail

PROJECT_NAME="cargo-tracker"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

sanitize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//'
}

echo "=== Build & push ${IMAGE_NAME} ==="

read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(sanitize "${IMAGE_TAG:-latest}")
IMAGE_TAG=${IMAGE_TAG:-latest}

echo "Select registry type:"
echo "  1. Azure Container Registry (ACR)"
echo "  2. Docker Hub"
read -r -p "Choice [1/2]: " REGISTRY_CHOICE

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "Enter ACR name (without .azurecr.io): " ACR_NAME
    [ -z "$ACR_NAME" ] && { echo "ACR name is required"; exit 1; }
    ACR_NAME=$(echo "$ACR_NAME" | tr '[:upper:]' '[:lower:]')
    echo "Logging in to ACR ${ACR_NAME}..."
    az acr login --name "$ACR_NAME"
    FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
    ;;
  2)
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    [ -z "$DOCKER_USERNAME" ] && { echo "Docker Hub username is required"; exit 1; }
    read -r -s -p "Enter Docker Hub password/token: " DOCKER_PASSWORD
    echo
    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    DOCKER_USERNAME=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    ;;
  *)
    echo "Invalid choice"; exit 1 ;;
esac

echo
echo "Database settings are filtered into web.xml at build time (Maven 'cloud' profile)."
read -r -p "PostgreSQL JDBC URL [jdbc:postgresql://postgres:5432/postgres]: " POSTGRES_JDBC_URL
POSTGRES_JDBC_URL=${POSTGRES_JDBC_URL:-jdbc:postgresql://postgres:5432/postgres}
read -r -p "PostgreSQL username [cargotracker]: " POSTGRES_USERNAME
POSTGRES_USERNAME=${POSTGRES_USERNAME:-cargotracker}
read -r -s -p "PostgreSQL password [cargotracker]: " POSTGRES_PASSWORD
echo
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-cargotracker}

echo "Building image ${FULL_IMAGE_NAME}..."
docker build -f Dockerfile \
  --build-arg "POSTGRES_JDBC_URL=${POSTGRES_JDBC_URL}" \
  --build-arg "POSTGRES_USERNAME=${POSTGRES_USERNAME}" \
  --build-arg "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  -t "$FULL_IMAGE_NAME" .

echo "Pushing image ${FULL_IMAGE_NAME}..."
docker push "$FULL_IMAGE_NAME"

echo
echo "Done. Image pushed: ${FULL_IMAGE_NAME}"
echo "Use this URI with scripts/deploy-image.sh"
