@echo off
setlocal enabledelayedexpansion
REM Deploy cargo-tracker to Azure AKS. Run from the repository root:  scripts\deploy-image.bat

set "APP_NAME=cargo-tracker"
set "NAMESPACE=cargo-tracker"

where az >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo Azure CLI ^(az^) is required
  exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
  echo kubectl is required
  exit /b 1
)

set "RESOURCE_GROUP="
set "CLUSTER_NAME="
set "IMAGE_URI="
set /p RESOURCE_GROUP="Azure resource group: "
if "!RESOURCE_GROUP!"=="" (
  echo Resource group is required
  exit /b 1
)
set /p CLUSTER_NAME="AKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo AKS cluster name is required
  exit /b 1
)
set /p IMAGE_URI="Docker image URI (e.g. myacr.azurecr.io/cargo-tracker:latest): "
if "!IMAGE_URI!"=="" (
  echo Image URI is required
  exit /b 1
)

echo Application configuration (optional, press Enter to skip)
set "REDIS_HOST="
set "REDIS_PORT="
set "REDIS_SSL="
set "REDIS_PASSWORD="
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter for 6380): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6380"
set /p REDIS_SSL="Enter value for REDIS_SSL (or press Enter for true): "
if "!REDIS_SSL!"=="" set "REDIS_SSL=true"
set /p REDIS_PASSWORD="Enter value for REDIS_PASSWORD (or press Enter to skip): "

REM Work on a copy so the template manifests keep their placeholders
set "WORK_DIR=%TEMP%\cargo-tracker-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul
if !ERRORLEVEL! neq 0 (
  echo Failed to copy manifests. Run this script from the repository root.
  exit /b 1
)

set "TPL_IMAGE_URI=!IMAGE_URI!"
set "TPL_REDIS_HOST=!REDIS_HOST!"
set "TPL_REDIS_PORT=!REDIS_PORT!"
set "TPL_REDIS_SSL=!REDIS_SSL!"
powershell -NoProfile -Command "Get-ChildItem -Path '!WORK_DIR!' -Filter *.yaml | ForEach-Object { $c = Get-Content -Raw $_.FullName; $c = $c.Replace('{{IMAGE_URI}}', $env:TPL_IMAGE_URI).Replace('{{NAMESPACE}}', '!NAMESPACE!').Replace('{{REDIS_HOST}}', $env:TPL_REDIS_HOST).Replace('{{REDIS_PORT}}', $env:TPL_REDIS_PORT).Replace('{{REDIS_SSL}}', $env:TPL_REDIS_SSL); Set-Content -Path $_.FullName -Value $c -NoNewline }"
if !ERRORLEVEL! neq 0 (
  echo Failed to update manifests
  exit /b 1
)

echo Configuring kubectl for !CLUSTER_NAME!...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
  echo Failed to get AKS credentials
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Cannot reach cluster
  exit /b 1
)

echo Applying namespace...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply namespace
  exit /b 1
)

echo Applying secret...
kubectl create secret generic cargo-tracker-secrets --namespace !NAMESPACE! --from-literal=REDIS_PASSWORD="!REDIS_PASSWORD!" --dry-run=client -o yaml > "!WORK_DIR!\secret.generated"
if !ERRORLEVEL! neq 0 (
  echo Failed to generate secret
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\secret.generated"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply secret
  exit /b 1
)

echo Applying deployment, service and ingress...
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply deployment
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply service
  exit /b 1
)
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
  echo Failed to apply ingress
  exit /b 1
)

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=600s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  echo Inspect with: kubectl describe pods -n !NAMESPACE!
  exit /b 1
)

echo.
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo Ingress address: run  kubectl get ingress -n !NAMESPACE!  (host rule cargo-tracker.example.com)
echo Quick test: kubectl port-forward svc/!APP_NAME!-service 8080:80 -n !NAMESPACE!

rmdir /s /q "!WORK_DIR!"
endlocal
