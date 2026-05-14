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
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Error: Docker is not accessible. Start Docker or configure passwordless Docker access for this user." >&2
  exit 1
fi

HERMES_NAME="${HERMES_CONTAINER_NAME:-hermes}"
INNER_DOCKER_NAME="${INNER_DOCKER_CONTAINER_NAME:-inner-docker}"
GATEWAY_NAME="${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}"
HERMES_USER="${HERMES_UID:-10000}:${HERMES_GID:-10000}"
SENTINEL="HERMES_DOCKER_DEPLOYMENT_REAL_TEST_OK"
LOG_DIR="${SMOKE_LOG_DIR:-logs}"
ASK_LOG="$LOG_DIR/ask-yui-real-smoke.log"

mkdir -p "$LOG_DIR"

echo "Checking host containers..."
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$HERMES_NAME" | grep -qx true
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$INNER_DOCKER_NAME" | grep -qx true

echo "Checking L2 Docker and MCP Gateway..."
"${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 info >/dev/null
"${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 inspect -f '{{.State.Running}}' "$GATEWAY_NAME" | grep -qx true
"${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 volume ls --format '{{.Name}}' | grep -x hermes-mcp-config >/dev/null
"${DOCKER[@]}" exec "$INNER_DOCKER_NAME" docker -H tcp://127.0.0.1:2375 logs --tail 120 "$GATEWAY_NAME" 2>&1 | grep -q 'profile-manager: ('

echo "Checking Hermes sees L2 Docker..."
"${DOCKER[@]}" exec --user "$HERMES_USER" "$HERMES_NAME" sh -lc \
  'docker ps --format "{{.Names}}" | grep -x mcp-gateway >/dev/null'

echo "Checking Hermes MCP registration..."
"${DOCKER[@]}" exec --user "$HERMES_USER" "$HERMES_NAME" sh -lc \
  'cd /opt/hermes && /opt/hermes/.venv/bin/hermes mcp list | grep -q docker-gateway'

echo "Running real ask_yui test..."
cat >"$LOG_DIR/ask-yui-real-smoke.prompt" <<EOF
请做一次真实部署验收，只使用只读检查。

要求：
1. 使用 terminal 执行 docker ps --format '{{.Names}}'，确认能看到 mcp-gateway。
2. 如果可以，请再查看 Hermes MCP 配置中是否存在 docker-gateway。
3. 如果上述检查通过，只回复：$SENTINEL

不要解释，不要输出表格。
EOF

if ! "$PWD/scripts/ask-yui.sh" <"$LOG_DIR/ask-yui-real-smoke.prompt" | tee "$ASK_LOG"; then
  echo "Error: ask_yui smoke test failed. See $ASK_LOG" >&2
  exit 1
fi

if ! grep -q "$SENTINEL" "$ASK_LOG"; then
  echo "Error: ask_yui did not return sentinel $SENTINEL. See $ASK_LOG" >&2
  exit 1
fi

echo "$SENTINEL"
