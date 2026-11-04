#!/bin/sh
# Container entrypoint: injects runtime configuration into the exploded WAR
# and starts Payara Server in the foreground.
set -e

APP_DIR="/opt/payara/deployments/cargo-tracker"
WEB_XML="${APP_DIR}/WEB-INF/web.xml"

if [ -z "${DB_JDBC_URL}" ]; then
  echo "ERROR: DB_JDBC_URL is required (e.g. jdbc:postgresql://host:5432/postgres)" >&2
  exit 1
fi

# XML-escape the value, then escape characters special to the sed replacement
esc() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    | sed -e 's/[\\|&]/\\&/g'
}

sed -i "s|__DB_JDBC_URL__|$(esc "${DB_JDBC_URL}")|g" "${WEB_XML}"
sed -i "s|__DB_USER__|$(esc "${DB_USER:-}")|g" "${WEB_XML}"
sed -i "s|__DB_PASSWORD__|$(esc "${DB_PASSWORD:-}")|g" "${WEB_XML}"

if [ -n "${GRAPH_TRAVERSAL_URL}" ]; then
  sed -i "s|http://localhost:8080/rest/graph-traversal/shortest-path|$(esc "${GRAPH_TRAVERSAL_URL}")|g" "${WEB_XML}"
fi

echo "Starting Payara Server (cargo-tracker) ..."
exec /opt/payara/bin/asadmin start-domain --verbose \
  --postbootcommandfile /opt/payara/post-boot-commands.asadmin domain1
