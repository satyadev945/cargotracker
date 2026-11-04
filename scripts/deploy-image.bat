@echo off
setlocal enabledelayedexpansion

rem Deploy cargo-tracker to AWS EKS.
rem Run from the repository root: scripts\deploy-image.bat

cd /d "%~dp0.."

set "APP_NAME=cargo-tracker"
set "NAMESPACE=cargo-tracker"

where aws >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR aws cli is required
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo ERROR kubectl is required
  exit /b 1
)

echo === Cargo Tracker - deploy to AWS EKS ===
set /p AWS_REGION="Enter AWS region (e.g. us-east-1): "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"
set /p CLUSTER_NAME="Enter EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo ERROR cluster name is required
  exit /b 1
)
set /p IMAGE_URI="Enter Docker image URI (registry/repo:tag): "
if "!IMAGE_URI!"=="" (
  echo ERROR image URI is required
  exit /b 1
)

echo --- Application configuration ---
set /p DB_JDBC_URL="Enter value for DB_JDBC_URL (jdbc:postgresql://host:5432/postgres): "
if "!DB_JDBC_URL!"=="" (
  echo ERROR DB_JDBC_URL is required
  exit /b 1
)
set /p DB_USER="Enter value for DB_USER (or press Enter to skip): "
set /p DB_PASSWORD="Enter value for DB_PASSWORD (or press Enter to skip): "
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT="Enter value for REDIS_PORT (default 6379): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"

rem Work on a temporary copy so the template manifests stay untouched
set "WORK_DIR=%TEMP%\cargo-tracker-k8s"
if exist "!WORK_DIR!" rmdir /s /q "!WORK_DIR!"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

set "CT_IMAGE_URI=!IMAGE_URI!"
set "CT_REDIS_HOST=!REDIS_HOST!"
set "CT_REDIS_PORT=!REDIS_PORT!"
powershell -NoProfile -Command "$f='!WORK_DIR!\deployment.yaml'; (Get-Content -Raw $f).Replace('{{IMAGE_URI}}',$env:CT_IMAGE_URI).Replace('{{REDIS_HOST}}',$env:CT_REDIS_HOST).Replace('{{REDIS_PORT}}',$env:CT_REDIS_PORT) | Set-Content -NoNewline $f"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl for cluster !CLUSTER_NAME! ...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo ERROR cannot reach the cluster
  exit /b 1
)

echo Applying namespace ...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
  echo Namespace apply failed
  exit /b 1
)

echo Creating or updating database secret ...
kubectl create secret generic cargo-tracker-db -n !NAMESPACE! --from-literal=DB_JDBC_URL="!DB_JDBC_URL!" --from-literal=DB_USER="!DB_USER!" --from-literal=DB_PASSWORD="!DB_PASSWORD!" --dry-run=client -o yaml > "!WORK_DIR!\secret.yaml"
if !ERRORLEVEL! neq 0 (
  echo Secret generation failed
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\secret.yaml"
if !ERRORLEVEL! neq 0 (
  echo Secret apply failed
  exit /b 1
)

echo Applying deployment, service and ingress ...
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
  echo Deployment apply failed
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
  echo Service apply failed
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
  echo Ingress apply failed
  exit /b 1
)

echo Waiting for rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=600s
if !ERRORLEVEL! neq 0 (
  echo ERROR rollout failed. Inspect with:
  echo   kubectl describe pods -n !NAMESPACE! -l app=!APP_NAME!
  echo   kubectl logs -n !NAMESPACE! -l app=!APP_NAME! --tail=100
  echo Roll back with:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

echo Resources in namespace !NAMESPACE!:
kubectl get pods,svc,ingress -n !NAMESPACE!

echo Ingress address:
kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo.
echo Open http://INGRESS_ADDRESS/ in a browser. If empty, wait a few minutes and re-run
echo   kubectl get ingress -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!" >nul 2>&1
endlocal
