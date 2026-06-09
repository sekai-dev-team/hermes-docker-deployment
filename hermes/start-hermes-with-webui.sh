#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
HERMES_INSTALL_DIR="${HERMES_INSTALL_DIR:-/opt/hermes}"
HERMES_WEBUI_ENABLED="${HERMES_WEBUI_ENABLED:-1}"
HERMES_WEBUI_DIR="${HERMES_WEBUI_DIR:-${HERMES_HOME}/hermes-webui}"
HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"
HERMES_WEBUI_STATE_DIR="${HERMES_WEBUI_STATE_DIR:-${HERMES_HOME}/webui}"
HERMES_GATEWAY_URL="${HERMES_GATEWAY_URL:-http://127.0.0.1:8642}"
HERMES_WEBUI_AGENT_DIR="${HERMES_WEBUI_AGENT_DIR:-${HERMES_INSTALL_DIR}}"

start_webui() {
  case "${HERMES_WEBUI_ENABLED}" in
    1|true|TRUE|True|yes|YES|Yes) ;;
    *)
      echo "Hermes WebUI disabled (HERMES_WEBUI_ENABLED=${HERMES_WEBUI_ENABLED})"
      return 0
      ;;
  esac

  if [ ! -f "${HERMES_WEBUI_DIR}/server.py" ]; then
    echo "Hermes WebUI not found at ${HERMES_WEBUI_DIR}/server.py; skipping WebUI startup"
    return 0
  fi

  mkdir -p "${HERMES_WEBUI_STATE_DIR}" "${HERMES_HOME}/logs"
  echo "Starting Hermes WebUI on ${HERMES_WEBUI_HOST}:${HERMES_WEBUI_PORT} from ${HERMES_WEBUI_DIR}"
  (
    cd "${HERMES_WEBUI_DIR}"
    export HERMES_HOME
    export HERMES_WEBUI_STATE_DIR
    export HERMES_WEBUI_HOST
    export HERMES_WEBUI_PORT
    export HERMES_GATEWAY_URL
    export HERMES_WEBUI_AGENT_DIR
    exec "${HERMES_INSTALL_DIR}/.venv/bin/python" server.py
  ) 2>&1 | sed -u 's/^/[webui] /' &
}

start_webui

if [ "$#" -eq 0 ]; then
  set -- gateway run
fi

exec "${HERMES_INSTALL_DIR}/.venv/bin/hermes" "$@"
