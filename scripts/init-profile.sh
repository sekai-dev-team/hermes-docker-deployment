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
PROFILE_MANAGER_ALLOWED_SERVERS="${PROFILE_MANAGER_ALLOWED_SERVERS:-fetch}"
PROFILE_MANAGER_TEMPLATE="$PWD/catalog/profile-manager.yaml.template"
PROFILE_MANAGER_GENERATED="$PWD/catalog/profile-manager.generated.yaml"
PROFILE_MANAGER_REF="file:///catalog/profile-manager.generated.yaml"

"${DOCKER_COMPOSE[@]}" build profile-manager
"${DOCKER[@]}" volume create hermes-mcp-config >/dev/null

sed \
  -e "s|@PROFILE_ID@|$PROFILE|g" \
  -e "s|@CATALOG_REF@|$CATALOG|g" \
  -e "s|@PROFILE_MANAGER_IMAGE@|$PROFILE_MANAGER_IMAGE|g" \
  -e "s|@ALLOWED_SERVERS@|$PROFILE_MANAGER_ALLOWED_SERVERS|g" \
  "$PROFILE_MANAGER_TEMPLATE" >"$PROFILE_MANAGER_GENERATED"

MCP_RUN=(
  "${DOCKER[@]}" run --rm
  --entrypoint /docker-mcp
  -v hermes-mcp-config:/root/.docker/mcp
  -v "$PWD/catalog:/catalog:ro"
  "${MCP_GATEWAY_IMAGE:-docker/mcp-gateway:latest}"
)

"${MCP_RUN[@]}" catalog pull "$CATALOG"

if "${MCP_RUN[@]}" profile show "$PROFILE" >/dev/null 2>&1; then
  "${MCP_RUN[@]}" profile server remove "$PROFILE" profile-manager >/dev/null 2>&1 || true
  "${MCP_RUN[@]}" profile server add "$PROFILE" --server "$PROFILE_MANAGER_REF"
else
  "${MCP_RUN[@]}" profile create --name "$PROFILE" --id "$PROFILE" --server "$PROFILE_MANAGER_REF"
fi

echo "Initialized Docker MCP profile: $PROFILE"
echo "Profile manager server: $PROFILE_MANAGER_REF"
