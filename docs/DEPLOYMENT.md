# Cargo Tracker – Deployment Guide (Docker & Azure AKS)

## 1. Overview
Eclipse Cargo Tracker is a Jakarta EE 10 WAR (Maven, Java 11 release level, packaging `war`). In the container it runs on **Payara Micro 6.2025.5** on top of `eclipse-temurin:11-jdk-alpine`.

| Item | Value |
|------|-------|
| Build tool | Maven (`mvn`, wrapper not used) – `cloud` profile |
| Artifact | `target/cargo-tracker.war` (deployed as `ROOT.war`, context root `/`) |
| Port | 8080 (HTTP) |
| Health endpoint | `GET /rest/health` → `{"status":"UP"}` |
| Database | PostgreSQL (external; JDBC settings filtered into `web.xml` at **build time**) |
| Cache (optional) | Azure Cache for Redis via `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `REDIS_SSL` |

## 2. Prerequisites
- Docker 20.10+ (BuildKit), Azure CLI 2.50+, kubectl, Azure subscription
- An ACR (or Docker Hub account), an AKS cluster with the Application Gateway Ingress Controller (AGIC) add-on
- A reachable PostgreSQL database (e.g. Azure Database for PostgreSQL)

## 3. Local development with Docker Compose
```bash
export POSTGRES_JDBC_URL="jdbc:postgresql://host.docker.internal:5432/postgres"
export POSTGRES_USERNAME=cargotracker
export POSTGRES_PASSWORD=cargotracker
docker compose up --build
curl http://localhost:8080/rest/health
```
The compose file only defines the application; start PostgreSQL separately (e.g. `docker run -e POSTGRES_USER=cargotracker -e POSTGRES_PASSWORD=cargotracker -p 5432:5432 postgres:16`).

## 4. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script prompts for the tag (default `latest`, sanitized to lowercase), registry (1. ACR, 2. Docker Hub) and the PostgreSQL build values. For ACR it runs `az acr login --name <acr>`.

> **Security note:** the JDBC URL/user/password are baked into the WAR (`web.xml` filtering) and therefore into the image layers. Push only to a **private** registry and consider moving the data source to the application server (Payara) or Azure Key Vault for production.

## 5. Deploy to AKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for resource group, cluster name, image URI and optional Redis settings, then:
1. Copies `kubernetes/*.yaml` to a temp directory and substitutes `{{IMAGE_URI}}`, `{{REDIS_HOST}}`, `{{REDIS_PORT}}`, `{{REDIS_SSL}}` (sed with `|` delimiter)
2. `az aks get-credentials` and `kubectl cluster-info`
3. Applies namespace → secret (`cargo-tracker-secrets`, holds `REDIS_PASSWORD`) → deployment → service → ingress
4. Waits for `kubectl rollout status deployment/cargo-tracker -n cargo-tracker`
5. Prints pods, services and ingress

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `cargo-tracker` |
| `kubernetes/deployment.yaml` | 2 replicas, startup/liveness/readiness probes on `/rest/health:8080`, requests 250m/512Mi, limits 500m/1Gi |
| `kubernetes/service.yaml` | ClusterIP `cargo-tracker-service` 80 → 8080 |
| `kubernetes/ingress.yaml` | AGIC ingress, host `cargo-tracker.example.com` (edit to your domain), cookie affinity |

Payara Micro starts with `--noCluster`; each replica is independent. Cookie-based affinity is enabled on the ingress so JSF sessions stay on one pod.

## 6. Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_PORT` | HTTP port | 8080 |
| `JAVA_OPTS` | JVM flags | `-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0 ...` |
| `TZ` | Timezone | UTC |
| `REDIS_HOST` | Azure Cache for Redis host (empty = disabled) | – |
| `REDIS_PORT` | Redis port | 6380 |
| `REDIS_PASSWORD` | Redis access key (Kubernetes Secret) | – |
| `REDIS_SSL` | Use TLS | true |

## 7. Operations
```bash
kubectl get pods -n cargo-tracker
kubectl logs deployment/cargo-tracker -n cargo-tracker
kubectl scale deployment/cargo-tracker --replicas=4 -n cargo-tracker
kubectl set image deployment/cargo-tracker cargo-tracker=<new-image> -n cargo-tracker
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker
kubectl autoscale deployment cargo-tracker --cpu-percent=70 --min=2 --max=6 -n cargo-tracker
```

## 8. Troubleshooting
- **Pod `ImagePullBackOff`**: attach ACR to AKS: `az aks update -g <rg> -n <cluster> --attach-acr <acr>`.
- **Pod restarts / `CrashLoopBackOff`**: check `kubectl logs`; usually the database is unreachable or JDBC values baked at build time are wrong – rebuild with correct values.
- **Not Ready for a long time**: Payara + JPA schema creation can take 1–3 minutes on 500m CPU; the startup probe allows ~5 minutes. Raise CPU limits if needed.
- **OOMKilled**: raise memory limit (and keep `MaxRAMPercentage` ≤ 70).
- **Ingress has no address**: verify AGIC add-on (`az aks show ... --query addonProfiles`) and `kubectl describe ingress -n cargo-tracker`.
- **502 from Application Gateway**: confirm the health probe path `/rest/health` returns 200.
- **Redis errors**: the app falls back to built-in defaults when Redis is unreachable; verify `REDIS_HOST`, TLS port 6380 and key.

## 9. Security
- Container runs as non-root (UID 1001); no package managers or extra tools in the runtime image.
- Store secrets in Kubernetes Secrets / Key Vault CSI driver; never commit credentials.
- Use a private registry and restrict ingress with TLS (add a `tls:` block and certificate).

## 10. Technology notes
- Build uses system `mvn` (no `mvnw`), cached dependency layer from `pom.xml`.
- The runtime base image is the explicitly requested `eclipse-temurin:11-jdk-alpine`; Payara Micro is copied from the builder stage (fetched with `mvn dependency:copy`).
- PostgreSQL driver is copied to `/app/lib/postgresql.jar` and loaded with `--addLibs`.
- Verify that the data source class configured in the `cloud` profile (`org.postgresql.ds.PGPoolingDataSource`) exists in the bundled PostgreSQL driver version; if not, change `db.driverClass` in `pom.xml` to `org.postgresql.ds.PGSimpleDataSource`.
