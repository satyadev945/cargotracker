#!/bin/bash
# Deploy cargo-tracker to Azure AKS. Run from the repository root:  ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="cargo-tracker"
NAMESPACE="cargo-tracker"

command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

read -r -p "Azure resource group: " RESOURCE_GROUP
[ -z "$RESOURCE_GROUP" ] && { echo "Resource group is required"; exit 1; }
read -r -p "AKS cluster name: " CLUSTER_NAME
[ -z "$CLUSTER_NAME" ] && { echo "AKS cluster name is required"; exit 1; }
read -r -p "Docker image URI (e.g. myacr.azurecr.io/cargo-tracker:latest): " IMAGE_URI
[ -z "$IMAGE_URI" ] && { echo "Image URI is required"; exit 1; }

echo "Application configuration (optional, press Enter to skip)"
read -r -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (or press Enter for 6380): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6380}
read -r -p "Enter value for REDIS_SSL (or press Enter for true): " REDIS_SSL
REDIS_SSL=${REDIS_SSL:-true}
read -r -s -p "Enter value for REDIS_PASSWORD (or press Enter to skip): " REDIS_PASSWORD
echo

# Escape characters that are special in sed replacement (\ | &)
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Work on a copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak \
    -e "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" \
    -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
    -e "s|{{REDIS_HOST}}|$(esc "$REDIS_HOST")|g" \
    -e "s|{{REDIS_PORT}}|$(esc "$REDIS_PORT")|g" \
    -e "s|{{REDIS_SSL}}|$(esc "$REDIS_SSL")|g" \
    "$f"
  rm -f "$f.bak"
done

echo "Configuring kubectl for ${CLUSTER_NAME}..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying namespace..."
kubectl apply -f "$WORK_DIR/namespace.yaml"

echo "Applying secret..."
kubectl create secret generic cargo-tracker-secrets \
  --namespace "$NAMESPACE" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applying deployment, service and ingress..."
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=600s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "Inspect with: kubectl describe pods -n ${NAMESPACE}; kubectl logs deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

echo
kubectl get pods,svc,ingress -n ${NAMESPACE}

echo
INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://${INGRESS_IP}/   (host rule: cargo-tracker.example.com)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n ${NAMESPACE}"
  echo "Quick test: kubectl port-forward svc/${APP_NAME}-service 8080:80 -n ${NAMESPACE}"
fi
