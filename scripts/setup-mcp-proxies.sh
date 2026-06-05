#!/usr/bin/env bash
# Sets up socat proxies for knowledge-mcp and pipeline-mcp on devwsl.
# Proxies bind on the hermes-mcp Docker network gateway so the hermes
# container (on hermes-mcp network) can reach devwsl services via Tailscale,
# bypassing mihomo TUN interface binding.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

KNOWLEDGE_MCP_HOST="${KNOWLEDGE_MCP_HOST:-}"
PIPELINE_MCP_HOST="${PIPELINE_MCP_HOST:-$KNOWLEDGE_MCP_HOST}"
PROXY_USER="${PROXY_USER:-$(id -un)}"

if [ -z "$KNOWLEDGE_MCP_HOST" ]; then
  echo "Skipping proxy setup: KNOWLEDGE_MCP_HOST not set in .env"
  exit 0
fi

# Detect hermes-mcp network gateway — this is the IP hermes uses to reach the host
HERMES_MCP_NETWORK="hermes-docker-deployment_hermes-mcp"
BIND_IP=$(docker network inspect "$HERMES_MCP_NETWORK" \
  --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.21.0.1")

echo "Detected hermes-mcp gateway: ${BIND_IP}"

if ! command -v socat &>/dev/null; then
  echo "Installing socat..."
  sudo apt-get install -y socat -q
fi

setup_proxy() {
  local name="$1" local_port="$2" remote_host="$3" remote_port="$4"
  local svc="${name}-proxy"

  sudo tee "/etc/${svc}.env" > /dev/null << ENVEOF
BIND_IP=${BIND_IP}
LOCAL_PORT=${local_port}
REMOTE_HOST=${remote_host}
REMOTE_PORT=${remote_port}
ENVEOF

  sed "s/^User=.*/User=${PROXY_USER}/" "$(pwd)/systemd/${svc}.service" | \
    sudo tee "/etc/systemd/system/${svc}.service" > /dev/null

  sudo systemctl daemon-reload
  sudo systemctl enable --now "$svc"
  echo "${svc}: ${BIND_IP}:${local_port} -> ${remote_host}:${remote_port}"
}

setup_proxy "knowledge-mcp" "8000" "$KNOWLEDGE_MCP_HOST" "8000"
setup_proxy "pipeline-mcp"  "8001" "$PIPELINE_MCP_HOST"  "8001"
