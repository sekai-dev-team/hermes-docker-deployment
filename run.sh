#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

while IFS= read -r line; do
  case "$line" in
    ""|\#*) continue ;;
  esac
  key=${line%%=*}
  if ! grep -q "^${key}=" .env; then
    printf '%s\n' "$line" >>.env
    echo "Added missing .env setting: $key"
  fi
done <.env.example

if grep -q '^HERMES_DATA_DIR=/home/<your_username>/.hermes$' .env; then
  default_data_dir="/home/$(id -un)/.hermes"
  sed -i "s|^HERMES_DATA_DIR=.*|HERMES_DATA_DIR=${default_data_dir}|" .env
  echo "Set HERMES_DATA_DIR to $default_data_dir"
fi

if grep -q '^HERMES_IMAGE=nousresearch/hermes-agent:latest$' .env; then
  sed -i 's|^HERMES_IMAGE=.*|HERMES_IMAGE=local/hermes-agent-docker-cli:latest|' .env
  echo "Updated HERMES_IMAGE for the Docker CLI-enabled Hermes image"
fi

if grep -Eq '^MCP_GATEWAY_URL=http://(mcp-gateway|yui-docker):8811/mcp$' .env; then
  sed -i 's|^MCP_GATEWAY_URL=.*|MCP_GATEWAY_URL=http://inner-docker:8811/mcp|' .env
  echo "Updated MCP_GATEWAY_URL for the inner L2 Gateway"
fi

if grep -q '^YUI_DOCKER_IMAGE=docker:27-dind-rootless$' .env; then
  sed -i 's|^YUI_DOCKER_IMAGE=.*|YUI_DOCKER_IMAGE=docker:27-dind|' .env
  echo "Updated legacy YUI_DOCKER_IMAGE to the supported DinD image"
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

"$PWD/scripts/init-profile.sh"
"$PWD/scripts/install-hermes-skill.sh"

"${DOCKER_COMPOSE[@]}" up -d --build --remove-orphans hermes
"${DOCKER_COMPOSE[@]}" ps

HERMES_NAME=${HERMES_CONTAINER_NAME:-hermes}
INNER_DOCKER_NAME=${INNER_DOCKER_CONTAINER_NAME:-inner-docker}
GATEWAY_NAME=${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}

"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$HERMES_NAME" | grep -qx true
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$INNER_DOCKER_NAME" | grep -qx true
"${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 inspect -f '{{.State.Running}}' "$GATEWAY_NAME" | grep -qx true

"${DOCKER[@]}" exec --user "${HERMES_UID:-10000}:${HERMES_GID:-10000}" "$HERMES_NAME" sh -lc \
  'cd /opt/hermes && /opt/hermes/.venv/bin/hermes mcp remove docker-gateway >/dev/null 2>&1 || true'
printf 'n\n\n' | "${DOCKER[@]}" exec --user "${HERMES_UID:-10000}:${HERMES_GID:-10000}" -i "$HERMES_NAME" sh -lc \
  "cd /opt/hermes && /opt/hermes/.venv/bin/hermes mcp add docker-gateway --url '${MCP_GATEWAY_URL:-http://inner-docker:8811/mcp}'"
echo "Hermes MCP server registered: docker-gateway"

echo
echo "Hermes gateway: http://127.0.0.1:${HERMES_GATEWAY_PORT:-8642}"
echo "Hermes dashboard: http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}"
echo "MCP Gateway: http://127.0.0.1:${MCP_GATEWAY_PORT:-8811}/mcp"
echo "Inner Docker: ${INNER_DOCKER_HOST:-tcp://inner-docker:2375}"
