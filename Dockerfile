# ---------------------------------------------------------------------------
# Eclipse Cargo Tracker - Jakarta EE 10 WAR running on Payara Server (full)
# Build context: repository root.  Example:
#   docker build -t cargo-tracker:latest .
# ---------------------------------------------------------------------------

# ============================ Builder stage ================================
FROM maven:3.9.4-eclipse-temurin-11 AS builder

ARG PAYARA_VERSION=6.2025.5

WORKDIR /workspace

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/*

# Cache Maven dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B -q -Pcloud dependency:resolve dependency:resolve-plugins || true

# Download and unpack the Payara Server distribution used at runtime
RUN mvn -B -q dependency:copy \
        -Dartifact=fish.payara.distributions:payara:${PAYARA_VERSION}:zip \
        -DoutputDirectory=/workspace/dist \
        -Dmdep.stripVersion=true \
    && unzip -q /workspace/dist/payara.zip -d /opt \
    && mv /opt/payara6 /opt/payara \
    && rm -rf /opt/payara/docs /workspace/dist \
    && sed -i -E 's|<jvm-options>-Xmx[0-9]+[mMgG]</jvm-options>|<jvm-options>-XX:MaxRAMPercentage=75.0</jvm-options>|g' \
        /opt/payara/glassfish/domains/domain1/config/domain.xml

# Copy the application source and build the "cloud" (PostgreSQL) profile.
# Database settings are written as placeholders and resolved at container start.
COPY . .
RUN mvn -B clean package -Pcloud -DskipTests -Dspotless.apply.skip=true \
        -DpostgreSqlJdbcUrl=__DB_JDBC_URL__ \
        -DpostgreSqlUsername=__DB_USER__ \
        -DpostgreSqlPassword=__DB_PASSWORD__ \
    && mkdir -p /opt/payara/deployments/cargo-tracker \
    && cd /opt/payara/deployments/cargo-tracker \
    && unzip -q /workspace/target/cargo-tracker.war \
    && cp /workspace/target/postgresql.jar /opt/payara/glassfish/domains/domain1/lib/postgresql.jar \
    && cp /workspace/docker/entrypoint.sh /opt/payara/entrypoint.sh \
    && cp /workspace/docker/post-boot-commands.asadmin /opt/payara/post-boot-commands.asadmin \
    && chmod 755 /opt/payara/entrypoint.sh \
    && chmod -R a+rX /opt/payara

# Make sure the Payara launch scripts are executable
RUN chmod -R 755 /opt/payara/bin /opt/payara/glassfish/bin \
    && (chmod 755 /opt/payara/glassfish/lib/nadmin || true)

# ============================ Runtime stage ================================
FROM amazoncorretto:11

LABEL org.opencontainers.image.title="cargo-tracker" \
      org.opencontainers.image.description="Eclipse Cargo Tracker (Jakarta EE 10 on Payara Server)"

ENV TZ=UTC \
    LANG=C.UTF-8 \
    HOME=/opt/payara \
    PAYARA_HOME=/opt/payara

# Run as an unprivileged numeric user (no package manager needed)
COPY --from=builder --chown=10001:10001 /opt/payara /opt/payara

WORKDIR /opt/payara
USER 10001:10001

# Application (HTTP) port
EXPOSE 8080

# Required at runtime: DB_JDBC_URL, DB_USER, DB_PASSWORD
# Optional: REDIS_HOST, REDIS_PORT, GRAPH_TRAVERSAL_URL
ENTRYPOINT ["/opt/payara/entrypoint.sh"]
