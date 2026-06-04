#!/usr/bin/env bash
# Sets up the socat proxy that lets the hermes Docker container reach
# knowledge-mcp on devwsl via Tailscale, bypassing mihomo's interface binding.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Load .env
if [ -f .env ]; then
  set -a; source .env; set +a
fi

KNOWLEDGE_MCP_HOST="${KNOWLEDGE_MCP_HOST:-}"
KNOWLEDGE_MCP_PORT="${KNOWLEDGE_MCP_PORT:-8000}"
KNOWLEDGE_MCP_LOCAL_PORT="${KNOWLEDGE_MCP_LOCAL_PORT:-8000}"
PROXY_USER="${PROXY_USER:-$(id -un)}"

if [ -z "$KNOWLEDGE_MCP_HOST" ]; then
  echo "Skipping knowledge-mcp proxy setup: KNOWLEDGE_MCP_HOST not set in .env"
  exit 0
fi

# Auto-detect docker bridge gateway IP
DOCKER_BRIDGE_IP=$(docker network inspect bridge \
  --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")

echo "Setting up knowledge-mcp-proxy: ${DOCKER_BRIDGE_IP}:${KNOWLEDGE_MCP_LOCAL_PORT} -> ${KNOWLEDGE_MCP_HOST}:${KNOWLEDGE_MCP_PORT}"

# Install socat if missing
if ! command -v socat &>/dev/null; then
  echo "Installing socat..."
  sudo apt-get install -y socat -q
fi

# Write env file for systemd
sudo tee /etc/knowledge-mcp-proxy.env > /dev/null << EOF
KNOWLEDGE_MCP_HOST=${KNOWLEDGE_MCP_HOST}
KNOWLEDGE_MCP_PORT=${KNOWLEDGE_MCP_PORT}
KNOWLEDGE_MCP_LOCAL_PORT=${KNOWLEDGE_MCP_LOCAL_PORT}
DOCKER_BRIDGE_IP=${DOCKER_BRIDGE_IP}
PROXY_USER=${PROXY_USER}
EOF

# Install and enable service
sudo cp "$(pwd)/systemd/knowledge-mcp-proxy.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now knowledge-mcp-proxy
echo "knowledge-mcp-proxy service enabled and running."
