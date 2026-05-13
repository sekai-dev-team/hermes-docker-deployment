#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -f .env ]; then
  echo ".env already exists"
else
  cp .env.example .env
  echo "Created .env from .env.example"
fi

if docker ps >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER_COMPOSE=(sudo docker compose)
else
  echo "Error: Docker is not accessible. Start Docker or configure permissions for this user." >&2
  exit 1
fi

SCRIPTS=(install.sh)
[ -f run.sh ] && SCRIPTS+=(run.sh)
bash -n "${SCRIPTS[@]}"

"${DOCKER_COMPOSE[@]}" config >/dev/null

echo "Hermes Docker deployment installed."
echo "For first-time Hermes setup, run:"
echo "docker run -it --rm -v /home/ubuntu/.hermes:/opt/data -e HERMES_UID=1000 -e HERMES_GID=1000 nousresearch/hermes-agent:latest setup"
echo "Then start Hermes with:"
echo "./run.sh"
