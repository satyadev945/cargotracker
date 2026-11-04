# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build the WAR (cloud profile), fetch Payara Micro and PostgreSQL JDBC driver
# ---------------------------------------------------------------------------
FROM maven:3.9.4-eclipse-temurin-11 AS builder

# Values filtered into WEB-INF/web.xml by the "cloud" Maven profile
ARG POSTGRES_JDBC_URL=jdbc:postgresql://postgres:5432/postgres
ARG POSTGRES_USERNAME=cargotracker
ARG POSTGRES_PASSWORD=cargotracker
ARG PAYARA_VERSION=6.2025.5

WORKDIR /workspace

# Cache dependencies: copy pom.xml first
COPY pom.xml .
RUN mvn -B -q -Pcloud dependency:go-offline -DskipTests || true

# Copy sources and build
COPY src ./src
RUN mvn -B clean package -Pcloud -DskipTests \
    -DpostgreSqlJdbcUrl="${POSTGRES_JDBC_URL}" \
    -DpostgreSqlUsername="${POSTGRES_USERNAME}" \
    -DpostgreSqlPassword="${POSTGRES_PASSWORD}"

# Fetch Payara Micro runtime (application server for the WAR)
RUN mvn -B dependency:copy \
    -Dartifact=fish.payara.extras:payara-micro:${PAYARA_VERSION}:jar \
    -DoutputDirectory=/workspace/payara \
    -Dmdep.stripVersion=true

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM eclipse-temurin:11-jdk-alpine

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    APP_HOME=/app \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0 -Xss512k -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

# Non-root user
RUN addgroup -S -g 1001 appgroup && adduser -S -u 1001 -G appgroup -h /app appuser

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /workspace/payara/payara-micro.jar /app/payara-micro.jar
COPY --from=builder --chown=appuser:appgroup /workspace/target/postgresql.jar /app/lib/postgresql.jar
COPY --from=builder --chown=appuser:appgroup /workspace/target/cargo-tracker.war /app/ROOT.war

RUN mkdir -p /app/data /tmp/payara && chown -R appuser:appgroup /app /tmp/payara

USER 1001:1001

EXPOSE 8080

# exec so that the JVM receives SIGTERM for graceful shutdown.
# ROOT.war is deployed at context root "/" ; health endpoint: /rest/health
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/payara-micro.jar --port ${SERVER_PORT} --noCluster --addLibs /app/lib/postgresql.jar --deploy /app/ROOT.war"]
