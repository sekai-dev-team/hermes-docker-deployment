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

SOURCE_DIR="$PWD/skills/docker-mcp-gateway-profile-manager"
TARGET_DIR="${HERMES_DATA_DIR:-/home/<your_username>/.hermes}/skills/devops/docker-mcp-gateway-profile-manager"

if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
  echo "Error: missing skill source: $SOURCE_DIR/SKILL.md" >&2
  exit 1
fi

if mkdir -p "$TARGET_DIR" 2>/dev/null && cp "$SOURCE_DIR/SKILL.md" "$TARGET_DIR/SKILL.md" 2>/dev/null; then
  :
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo mkdir -p "$TARGET_DIR"
  sudo cp "$SOURCE_DIR/SKILL.md" "$TARGET_DIR/SKILL.md"
else
  echo "Error: cannot write $TARGET_DIR. Run with a writable HERMES_DATA_DIR or passwordless sudo." >&2
  exit 1
fi

echo "Installed Yui skill: $TARGET_DIR/SKILL.md"
