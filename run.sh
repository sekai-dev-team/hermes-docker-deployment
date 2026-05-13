#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if docker ps >/dev/null 2>&1; then
  DOCKER=(docker)
  DOCKER_COMPOSE=(docker compose)
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER=(sudo docker)
  DOCKER_COMPOSE=(sudo docker compose)
else
  echo "Error: Docker is not accessible. Start Docker or configure passwordless Docker access for this user." >&2
  exit 1
fi

"${DOCKER_COMPOSE[@]}" up -d
"${DOCKER_COMPOSE[@]}" ps

HERMES_NAME=${HERMES_CONTAINER_NAME:-hermes}
GATEWAY_NAME=${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}

"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$HERMES_NAME" | rg '^true$' >/dev/null
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$GATEWAY_NAME" | rg '^true$' >/dev/null

echo
echo "Hermes gateway: http://127.0.0.1:${HERMES_GATEWAY_PORT:-8642}"
echo "Hermes dashboard: http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}"
echo "MCP Gateway: http://127.0.0.1:${MCP_GATEWAY_PORT:-8811}/mcp"
echo
echo "Manual Hermes MCP registration command:"
printf 'docker exec --user "%s:%s" -it "%s" sh -lc "cd /opt/hermes && /opt/hermes/.venv/bin/hermes mcp add docker-gateway --url '\''%s'\''"\n' \
  "${HERMES_UID:-1000}" \
  "${HERMES_GID:-1000}" \
  "$HERMES_NAME" \
  "${MCP_GATEWAY_URL:-http://mcp-gateway:8811/mcp}"
