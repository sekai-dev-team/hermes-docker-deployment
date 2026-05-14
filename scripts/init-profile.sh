#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
  echo "Error: Docker is not accessible. Start Docker or configure permissions for this user." >&2
  exit 1
fi

PROFILE="${MCP_GATEWAY_PROFILE:-hermes-default}"
CATALOG="${MCP_GATEWAY_CATALOG_REF:-mcp/docker-mcp-catalog:latest}"
PROFILE_MANAGER_IMAGE="${PROFILE_MANAGER_IMAGE:-local/hermes-profile-manager:latest}"
PROFILE_MANAGER_ALLOWED_SERVERS="${PROFILE_MANAGER_ALLOWED_SERVERS:-*}"
PROFILE_MANAGER_TEMPLATE="$PWD/catalog/profile-manager.yaml.template"
PROFILE_MANAGER_GENERATED="$PWD/catalog/profile-manager.generated.yaml"
PROFILE_MANAGER_REF="file:///catalog/profile-manager.generated.yaml"
INNER_DOCKER_NAME="${INNER_DOCKER_CONTAINER_NAME:-inner-docker}"
GATEWAY_NAME="${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}"
GATEWAY_IMAGE="${MCP_GATEWAY_IMAGE:-docker/mcp-gateway:latest}"
GATEWAY_TRANSPORT="${MCP_GATEWAY_TRANSPORT:-streaming}"

"${DOCKER_COMPOSE[@]}" up -d --remove-orphans inner-docker

for _ in $(seq 1 60); do
  if "${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! "${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 info >/dev/null 2>&1; then
  echo "Error: inner Docker daemon is not ready in $INNER_DOCKER_NAME." >&2
  exit 1
fi

sed \
  -e "s|@PROFILE_ID@|$PROFILE|g" \
  -e "s|@CATALOG_REF@|$CATALOG|g" \
  -e "s|@PROFILE_MANAGER_IMAGE@|$PROFILE_MANAGER_IMAGE|g" \
  -e "s|@ALLOWED_SERVERS@|$PROFILE_MANAGER_ALLOWED_SERVERS|g" \
  "$PROFILE_MANAGER_TEMPLATE" >"$PROFILE_MANAGER_GENERATED"

L2_DOCKER=(
  "${DOCKER[@]}" exec "$INNER_DOCKER_NAME"
  docker -H tcp://127.0.0.1:2375
)

"${L2_DOCKER[@]}" build -t "$PROFILE_MANAGER_IMAGE" /profile-manager
"${L2_DOCKER[@]}" volume create hermes-mcp-config >/dev/null

MCP_RUN=(
  "${L2_DOCKER[@]}" run --rm
  --entrypoint /docker-mcp
  -v hermes-mcp-config:/root/.docker/mcp
  -v /catalog:/catalog:ro
  "$GATEWAY_IMAGE"
)

"${MCP_RUN[@]}" catalog pull "$CATALOG"

if "${MCP_RUN[@]}" profile show "$PROFILE" >/dev/null 2>&1; then
  "${MCP_RUN[@]}" profile server remove "$PROFILE" profile-manager >/dev/null 2>&1 || true
  "${MCP_RUN[@]}" profile server add "$PROFILE" --server "$PROFILE_MANAGER_REF"
else
  "${MCP_RUN[@]}" profile create --name "$PROFILE" --id "$PROFILE" --server "$PROFILE_MANAGER_REF"
fi

"${L2_DOCKER[@]}" rm -f "$GATEWAY_NAME" >/dev/null 2>&1 || true
"${L2_DOCKER[@]}" run -d \
  --name "$GATEWAY_NAME" \
  --restart unless-stopped \
  -p 8811:8811 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v hermes-mcp-config:/root/.docker/mcp \
  -v /catalog:/catalog:ro \
  "$GATEWAY_IMAGE" \
  --port=8811 \
  --transport="$GATEWAY_TRANSPORT" \
  --profile="$PROFILE" \
  --watch >/dev/null

echo "Initialized Docker MCP profile: $PROFILE"
echo "Profile manager server: $PROFILE_MANAGER_REF"
echo "Started inner Docker MCP Gateway: $GATEWAY_NAME"
