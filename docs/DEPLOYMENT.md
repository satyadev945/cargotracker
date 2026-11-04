# Cargo Tracker - Deployment Guide (Docker & AWS EKS)

Eclipse Cargo Tracker is a Jakarta EE 10 application (`cargo-tracker.war`, Maven, Java 11) that runs on Payara Server.
The container packages the WAR built with the `cloud` Maven profile (PostgreSQL) together with Payara Server 6.2025.5 on
`amazoncorretto:11`.

| Item | Value |
|------|-------|
| Build tool | Maven (system `mvn`, no wrapper) |
| Packaging | WAR deployed to Payara Server at context root `/` |
| HTTP port | 8080 (admin port 4848 is not exposed) |
| Health endpoint | `GET /rest/health` -> `{"status":"UP"}` |
| Runtime image | `amazoncorretto:11` (explicit base image) |

## 1. Prerequisites

- Docker 20.10+ (BuildKit recommended)
- AWS CLI v2, `kubectl`, and (optionally) `eksctl`
- An AWS account with IAM permissions for ECR (`ecr:*` on the repository), EKS (`eks:DescribeCluster`) and, for the
  cluster, the AWS Load Balancer Controller
- A reachable PostgreSQL database (for example Amazon RDS). It is *not* part of these artifacts.
- Optional: Redis / Amazon ElastiCache for sharing SSE cargo updates between replicas

## 2. Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `DB_JDBC_URL` | yes | e.g. `jdbc:postgresql://mydb.xxxx.rds.amazonaws.com:5432/postgres` |
| `DB_USER` | no | database user |
| `DB_PASSWORD` | no | database password |
| `REDIS_HOST` | no | enables Redis (Jedis) when set |
| `REDIS_PORT` | no | default `6379` |
| `GRAPH_TRAVERSAL_URL` | no | overrides the built-in pathfinder URL (`http://localhost:8080/rest/graph-traversal/shortest-path`) |

The WAR is built once with placeholders (`__DB_JDBC_URL__`, `__DB_USER__`, `__DB_PASSWORD__`) in `WEB-INF/web.xml`.
`docker/entrypoint.sh` replaces them with the environment variable values when the container starts, so the same image
can be used in every environment and no credentials are baked into it.

## 3. Local development with Docker Compose

`docker-compose.yml` contains only the application service. Start PostgreSQL yourself, then:

```bash
export DB_JDBC_URL=jdbc:postgresql://host.docker.internal:5432/postgres
export DB_USER=cargotracker
export DB_PASSWORD=cargotracker
docker compose up --build
```

Open <http://localhost:8080/> and check <http://localhost:8080/rest/health>. The first start takes about 40-60 seconds.

## 4. Build and push the image

Run from the repository root:

```bash
./scripts/build-push.sh        # Linux / macOS
scripts\build-push.bat         # Windows
```

The script asks for the registry (1. AWS ECR, 2. Docker Hub), registry details and an image tag (sanitized,
default `latest`). For ECR it logs in and creates the repository if it does not exist. It then runs
`docker build -f Dockerfile -t <image> .` and `docker push`. Note the printed image URI.

Manual equivalent:

```bash
docker build -t cargo-tracker:latest .
```

## 5. AWS EKS setup

```bash
eksctl create cluster --name cargo-tracker --region us-east-1 --nodes 2 --node-type t3.large
aws eks update-kubeconfig --region us-east-1 --name cargo-tracker
kubectl get nodes
```

Install the **AWS Load Balancer Controller** (required by `kubernetes/ingress.yaml`, `kubernetes.io/ingress.class: alb`)
following the AWS documentation. Make sure the worker nodes can pull from ECR (the default node role does) and can reach
the database security group on port 5432.

## 6. Deploy to EKS

```bash
./scripts/deploy-image.sh      # Linux / macOS
scripts\deploy-image.bat       # Windows
```

The script prompts for the region, cluster name, image URI and the application variables above. It then:

1. copies `kubernetes/*.yaml` to a temp directory and replaces `{{IMAGE_URI}}`, `{{REDIS_HOST}}`, `{{REDIS_PORT}}`
   (the repository templates stay untouched);
2. runs `aws eks update-kubeconfig` and `kubectl cluster-info`;
3. applies `namespace.yaml`, creates/updates the `cargo-tracker-db` Secret (database settings), then applies
   `deployment.yaml`, `service.yaml`, `ingress.yaml`;
4. waits for `kubectl rollout status deployment/cargo-tracker -n cargo-tracker`, lists pods/services/ingress and prints
   the ALB hostname.

### Manifests

| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `cargo-tracker` |
| `kubernetes/deployment.yaml` | 2 replicas, non-root (uid 10001), startup/liveness/readiness probes on `/rest/health`, requests 250m/768Mi, limits 1000m/1536Mi |
| `kubernetes/service.yaml` | ClusterIP service `cargo-tracker-service`, port 80 -> 8080 |
| `kubernetes/ingress.yaml` | ALB ingress (internet-facing, `target-type: ip`, sticky sessions, health check `/rest/health`) |

Sticky sessions are enabled because the JSF UI is stateful. To use a custom domain or TLS, add a `host` rule and the
`alb.ingress.kubernetes.io/certificate-arn` + `listen-ports` (HTTPS 443) annotations.

## 7. Operations

```bash
kubectl get pods,svc,ingress -n cargo-tracker
kubectl logs -n cargo-tracker -l app=cargo-tracker --tail=200 -f
kubectl scale deployment/cargo-tracker -n cargo-tracker --replicas=4
kubectl autoscale deployment/cargo-tracker -n cargo-tracker --cpu-percent=70 --min=2 --max=6   # HPA (needs metrics-server)
kubectl set image deployment/cargo-tracker cargo-tracker=<new-image-uri> -n cargo-tracker       # rolling update
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker                                    # rollback
```

## 8. Troubleshooting

| Symptom | Checks |
|---------|--------|
| `ImagePullBackOff` | Wrong image URI/tag, missing ECR permissions: `kubectl describe pod ...` |
| `CrashLoopBackOff`, log says `DB_JDBC_URL is required` | Secret `cargo-tracker-db` missing/empty: `kubectl get secret cargo-tracker-db -n cargo-tracker` |
| Pod never Ready | Payara needs ~1 minute to start; startupProbe allows 5 minutes. Check logs for JDBC connection errors and database security groups |
| `OOMKilled` | Increase the memory limit; the JVM uses `MaxRAMPercentage=75` |
| Ingress has no address | AWS Load Balancer Controller not installed or subnets lack `kubernetes.io/role/elb=1` tags: `kubectl describe ingress -n cargo-tracker` |
| ALB targets unhealthy | Health check path must return 200: `kubectl port-forward svc/cargo-tracker-service 8080:80 -n cargo-tracker` then `curl localhost:8080/rest/health` |
| Real-time updates differ per pod | Set `REDIS_HOST` (ElastiCache) so SSE updates are shared across replicas |

## 9. Security considerations

- The container runs as non-root (uid/gid 10001); no package manager commands are executed in the runtime stage.
- Database credentials live in a Kubernetes Secret, not in the image or manifests. Consider AWS Secrets Manager with the
  Secrets Store CSI driver or External Secrets for production.
- Only port 8080 is exposed; the Payara admin console (4848) is not published. Terminate TLS at the ALB (ACM certificate).
- Restrict database/Redis security groups to the EKS node/pod security groups; enable ECR image scanning.

## 10. Java / Payara notes

- Build: `mvn clean package -Pcloud -DskipTests` (the Dockerfile runs it; the Maven wrapper is never used).
- JVM: `-Xmx` is replaced by `-XX:MaxRAMPercentage=75.0` in the Payara `domain.xml` so the heap follows the container limit.
- Time zone is `UTC` (`TZ=UTC`), locale `C.UTF-8`.
- The container is started with `asadmin start-domain --verbose`, which keeps Payara in the foreground; the pod has
  `terminationGracePeriodSeconds: 60` for a graceful shutdown.
- The embedded batch job scans `/tmp/uploads` for handling event files (mounted as a volume in Compose).
