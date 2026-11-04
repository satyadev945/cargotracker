#!/bin/bash
# Deploy cargo-tracker to AWS EKS.
# Run from the repository root:  ./scripts/deploy-image.sh
set -e
set -o pipefail

cd "$(dirname "$0")/.."

APP_NAME="cargo-tracker"
NAMESPACE="cargo-tracker"

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws cli is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is required"; exit 1; }

echo "=== Cargo Tracker - deploy to AWS EKS ==="
read -r -p "Enter AWS region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
[ -n "$CLUSTER_NAME" ] || { echo "ERROR: cluster name is required"; exit 1; }
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
[ -n "$IMAGE_URI" ] || { echo "ERROR: image URI is required"; exit 1; }

echo "--- Application configuration ---"
read -r -p "Enter value for DB_JDBC_URL (e.g. jdbc:postgresql://host:5432/postgres): " DB_JDBC_URL
[ -n "$DB_JDBC_URL" ] || { echo "ERROR: DB_JDBC_URL is required"; exit 1; }
read -r -p "Enter value for DB_USER (or press Enter to skip): " DB_USER
read -r -s -p "Enter value for DB_PASSWORD (or press Enter to skip): " DB_PASSWORD
echo
read -r -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT [6379]: " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}

# Escape a value for use in the replacement part of sed with '|' delimiter
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i 's|{{IMAGE_URI}}|'"$(sed_escape "$IMAGE_URI")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{REDIS_HOST}}|'"$(sed_escape "$REDIS_HOST")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{REDIS_PORT}}|'"$(sed_escape "$REDIS_PORT")"'|g' "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl for cluster ${CLUSTER_NAME} ..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "ERROR: cannot reach the cluster"; exit 1; }

echo "Applying namespace ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"

echo "Creating/updating database secret ..."
kubectl create secret generic cargo-tracker-db -n "$NAMESPACE" \
  --from-literal=DB_JDBC_URL="$DB_JDBC_URL" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applying deployment, service and ingress ..."
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/${APP_NAME} -n "$NAMESPACE" --timeout=600s; then
  echo "ERROR: rollout failed. Inspect with:"
  echo "  kubectl describe pods -n ${NAMESPACE} -l app=${APP_NAME}"
  echo "  kubectl logs -n ${NAMESPACE} -l app=${APP_NAME} --tail=100"
  echo "Roll back with:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

echo "Resources in namespace ${NAMESPACE}:"
kubectl get pods,svc,ingress -n "$NAMESPACE"

echo "Waiting for the load balancer address (up to ~3 minutes) ..."
INGRESS_HOST=""
for _ in $(seq 1 18); do
  INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$INGRESS_HOST" ] && break
  sleep 10
done

if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://${INGRESS_HOST}/"
else
  echo "Ingress address not yet assigned. Check later with:"
  echo "  kubectl get ingress -n ${NAMESPACE}"
  echo "(requires the AWS Load Balancer Controller to be installed in the cluster)"
fi
