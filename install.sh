#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -f .env ]; then
  echo ".env already exists"
else
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

SCRIPTS=(install.sh)
[ -f run.sh ] && SCRIPTS+=(run.sh)
for script in "${SCRIPTS[@]}"; do
  bash -n "$script"
done

"${DOCKER_COMPOSE[@]}" config >/dev/null

echo "Hermes Docker deployment installed."
echo "For first-time Hermes setup, run:"
printf '%s run -it --rm -v %s:/opt/data -e HERMES_UID=%s -e HERMES_GID=%s %s setup\n' \
  "${DOCKER[*]}" \
  "${HERMES_DATA_DIR:-/home/<your_username>/.hermes}" \
  "${HERMES_UID:-10000}" \
  "${HERMES_GID:-10000}" \
  "${HERMES_IMAGE:-nousresearch/hermes-agent:latest}"
echo "Then start Hermes with:"
echo "./run.sh"
