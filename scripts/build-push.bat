@echo off
setlocal enabledelayedexpansion
REM Build and push the cargo-tracker Docker image. Run from the repository root:  scripts\build-push.bat

set "PROJECT_NAME=cargo-tracker"
set "IMAGE_NAME=cargo-tracker"

echo === Build and push !IMAGE_NAME! ===

set "IMAGE_TAG="
set /p IMAGE_TAG="Enter image tag [latest]: "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
powershell -NoProfile -Command "$t='!IMAGE_TAG!'.ToLower(); $t=[regex]::Replace($t,'[^a-z0-9._-]+','-').Trim('-'); if([string]::IsNullOrEmpty($t)){$t='latest'}; Set-Content -Path $env:TEMP\image_tag.txt -Value $t -NoNewline"
if !ERRORLEVEL! neq 0 (
  echo Tag sanitization failed
  exit /b 1
)
set /p IMAGE_TAG=<"%TEMP%\image_tag.txt"

echo Select registry type:
echo   1. Azure Container Registry (ACR)
echo   2. Docker Hub
set "REGISTRY_CHOICE="
set /p REGISTRY_CHOICE="Choice [1/2]: "

if "!REGISTRY_CHOICE!"=="1" goto acr
if "!REGISTRY_CHOICE!"=="2" goto dockerhub
echo Invalid choice
exit /b 1

:acr
set "ACR_NAME="
set /p ACR_NAME="Enter ACR name (without .azurecr.io): "
if "!ACR_NAME!"=="" (
  echo ACR name is required
  exit /b 1
)
echo Logging in to ACR !ACR_NAME!...
az acr login --name !ACR_NAME!
if !ERRORLEVEL! neq 0 (
  echo ACR login failed
  exit /b 1
)
set "REGISTRY_PREFIX=!ACR_NAME!.azurecr.io"
goto build

:dockerhub
set "DOCKER_USERNAME="
set "DOCKER_PASSWORD="
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password/token: "
if "!DOCKER_USERNAME!"=="" (
  echo Docker Hub username is required
  exit /b 1
)
echo !DOCKER_PASSWORD!| docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
  echo Docker Hub login failed
  exit /b 1
)
set "REGISTRY_PREFIX=!DOCKER_USERNAME!"
goto build

:build
set "POSTGRES_JDBC_URL="
set "POSTGRES_USERNAME="
set "POSTGRES_PASSWORD="
echo Database settings are filtered into web.xml at build time (Maven cloud profile).
set /p POSTGRES_JDBC_URL="PostgreSQL JDBC URL [jdbc:postgresql://postgres:5432/postgres]: "
if "!POSTGRES_JDBC_URL!"=="" set "POSTGRES_JDBC_URL=jdbc:postgresql://postgres:5432/postgres"
set /p POSTGRES_USERNAME="PostgreSQL username [cargotracker]: "
if "!POSTGRES_USERNAME!"=="" set "POSTGRES_USERNAME=cargotracker"
set /p POSTGRES_PASSWORD="PostgreSQL password [cargotracker]: "
if "!POSTGRES_PASSWORD!"=="" set "POSTGRES_PASSWORD=cargotracker"

set "FULL_IMAGE_NAME=!REGISTRY_PREFIX!/!IMAGE_NAME!:!IMAGE_TAG!"
echo Building image !FULL_IMAGE_NAME!...
docker build -f Dockerfile --build-arg "POSTGRES_JDBC_URL=!POSTGRES_JDBC_URL!" --build-arg "POSTGRES_USERNAME=!POSTGRES_USERNAME!" --build-arg "POSTGRES_PASSWORD=!POSTGRES_PASSWORD!" -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
  echo Docker build failed
  exit /b 1
)

echo Pushing image !FULL_IMAGE_NAME!...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
  echo Docker push failed
  exit /b 1
)

echo.
echo Done. Image pushed: !FULL_IMAGE_NAME!
echo Use this URI with scripts\deploy-image.bat
endlocal
