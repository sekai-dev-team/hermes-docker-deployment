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

PROMPT="${*:-}"
if [ -z "$PROMPT" ]; then
  if [ -t 0 ]; then
    echo "usage: $0 <prompt>" >&2
    echo "       printf 'prompt' | $0" >&2
    exit 2
  fi
  PROMPT="$(cat)"
fi

if docker ps >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Error: Docker is not accessible. Start Docker or configure passwordless Docker access for this user." >&2
  exit 1
fi

HERMES_NAME="${HERMES_CONTAINER_NAME:-hermes}"
HERMES_USER="${HERMES_UID:-10000}:${HERMES_GID:-10000}"
HERMES_BIN="/opt/hermes/.venv/bin/hermes"
ASK_YUI_TIMEOUT="${ASK_YUI_TIMEOUT:-300}"

printf '%s' "$PROMPT" | timeout "$ASK_YUI_TIMEOUT" "${DOCKER[@]}" exec --user "$HERMES_USER" -i "$HERMES_NAME" sh -lc '
cd /opt/hermes
PROMPT="$(cat)"
"$1" -z "$PROMPT"
' sh "$HERMES_BIN"
