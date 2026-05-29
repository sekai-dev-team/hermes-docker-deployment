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

"${DOCKER_COMPOSE[@]}" up -d --remove-orphans inner-docker
"${DOCKER_COMPOSE[@]}" up -d --build --remove-orphans hermes
"${DOCKER_COMPOSE[@]}" ps

HERMES_NAME=${HERMES_CONTAINER_NAME:-hermes}
INNER_DOCKER_NAME=${INNER_DOCKER_CONTAINER_NAME:-inner-docker}

"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$HERMES_NAME" | grep -qx true
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$INNER_DOCKER_NAME" | grep -qx true

echo
echo "Hermes gateway: http://127.0.0.1:${HERMES_GATEWAY_PORT:-8642}"
echo "Hermes dashboard: http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}"
echo "Inner Docker: ${INNER_DOCKER_HOST:-tcp://inner-docker:2375}"
echo
echo "MCP servers are registered in config.yaml — see README.md for details."
