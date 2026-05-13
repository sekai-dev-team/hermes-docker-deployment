# Hermes Docker Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new minimal deployment repository that runs official Hermes with Docker MCP Gateway and documents migration away from `yui-ecosystem`.

**Architecture:** The stack has two long-running services: `hermes` and `mcp-gateway`. Hermes uses `nousresearch/hermes-agent:latest`, never mounts docker.sock, and self-restarts through `kill 1` plus Compose `restart: always`; Docker MCP Gateway is the only service with docker.sock access and acts as the MCP aggregation point.

**Tech Stack:** Docker Compose, Bash, Docker MCP Gateway, Hermes official Docker image, Markdown docs.

---

## File Structure

- Create: `.env.example`
  - Holds all configurable ports, image names, container names, data paths, and Gateway connection values.
- Create: `docker-compose.yml`
  - Defines `hermes` and `mcp-gateway` services on one network.
- Create: `install.sh`
  - Performs host checks, creates `.env`, validates scripts, and validates Compose.
- Create: `run.sh`
  - Starts the stack and verifies container state. It prints or performs Hermes MCP Gateway registration only after command verification.
- Create: `README.md`
  - Documents setup, operation, self-restart, Gateway integration, and security boundaries.
- Create: `docs/migration-from-yui-ecosystem.md`
  - Documents what is archived, removed, and mapped to Docker MCP Gateway.
- Modify: `docs/superpowers/specs/2026-05-13-hermes-docker-deployment-design.md`
  - Only if implementation verification discovers a real command-level fact that changes the design notes.

---

### Task 1: Verify Docker and Hermes Command Facts

**Files:**
- No file changes in this task unless verification proves the design needs a correction.

- [ ] **Step 1: Check Docker and Compose availability**

Run:

```bash
docker version
docker compose version
```

Expected: both commands exit 0. If `docker` requires sudo, use `sudo docker` consistently in the local verification notes and scripts should detect both direct Docker and passwordless sudo Docker.

- [ ] **Step 2: Check Docker MCP CLI availability**

Run:

```bash
docker mcp version
docker mcp gateway run --help
```

Expected: both commands exit 0 and `gateway run --help` lists `--port` and `--transport`.

If `docker mcp` is missing, run:

```bash
docker image inspect docker/mcp-gateway:latest
```

Expected: either the image exists locally or Docker can pull it during Compose verification. If neither CLI nor image route works, stop and document the missing Docker MCP Gateway installation requirement in the final response.

- [ ] **Step 3: Verify Gateway transport and endpoint route**

Prefer the Docker CLI plugin route if available. Start a temporary Gateway process:

```bash
timeout 10s docker mcp gateway run --port 8811 --transport streaming
```

Expected: command starts listening or exits only because `timeout` stopped it. It must not fail immediately with an unknown transport or unknown flag error.

If `streaming` is rejected, try:

```bash
timeout 10s docker mcp gateway run --port 8811 --transport sse
```

Expected: command starts listening or exits only because `timeout` stopped it. Record the working transport for `.env.example`, `docker-compose.yml`, `run.sh`, and README.

- [ ] **Step 4: Inspect official Hermes image CLI**

Run:

```bash
docker run --rm nousresearch/hermes-agent:latest sh -lc 'command -v hermes || true; ls -l /opt/hermes/.venv/bin/hermes 2>/dev/null || true; hermes --help 2>/dev/null || /opt/hermes/.venv/bin/hermes --help'
```

Expected: command exits 0 and shows a usable Hermes CLI path. Record the path as `HERMES_BIN` default.

- [ ] **Step 5: Inspect Hermes MCP command help**

Run, replacing the binary if Step 4 found a different path:

```bash
docker run --rm nousresearch/hermes-agent:latest sh -lc '/opt/hermes/.venv/bin/hermes mcp --help && /opt/hermes/.venv/bin/hermes mcp add --help'
```

Expected: command exits 0 and documents the accepted flags for MCP registration. Record whether transport must be passed explicitly.

- [ ] **Step 6: Commit verification notes only if design changes**

If verification changes the design assumptions, update the spec and commit:

```bash
git add docs/superpowers/specs/2026-05-13-hermes-docker-deployment-design.md
git commit -m "docs: update gateway verification findings"
```

Expected: commit is created only if the spec changed.

---

### Task 2: Add Environment and Compose Configuration

**Files:**
- Create: `.env.example`
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `.env.example`**

Add:

```dotenv
HERMES_IMAGE=nousresearch/hermes-agent:latest
HERMES_CONTAINER_NAME=hermes
HERMES_DATA_DIR=/home/ubuntu/.hermes
HERMES_GATEWAY_PORT=8642
HERMES_DASHBOARD_PORT=9119
HERMES_UID=1000
HERMES_GID=1000

MCP_GATEWAY_CONTAINER_NAME=mcp-gateway
MCP_GATEWAY_PORT=8811
MCP_GATEWAY_TRANSPORT=streaming
MCP_GATEWAY_URL=http://mcp-gateway:8811

COMPOSE_PROJECT_NAME=hermes-docker-deployment
```

If Task 1 proves a different transport or URL is required, use the verified values instead of `streaming` and `http://mcp-gateway:8811`.

- [ ] **Step 2: Create `docker-compose.yml`**

Add a Compose file with these properties:

```yaml
services:
  mcp-gateway:
    image: ${MCP_GATEWAY_IMAGE:-docker/mcp-gateway:latest}
    container_name: ${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${MCP_GATEWAY_PORT:-8811}:8811"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command:
      - "--port=8811"
      - "--transport=${MCP_GATEWAY_TRANSPORT:-streaming}"
    networks:
      - hermes-mcp

  hermes:
    image: ${HERMES_IMAGE:-nousresearch/hermes-agent:latest}
    container_name: ${HERMES_CONTAINER_NAME:-hermes}
    init: true
    user: root
    restart: always
    command: gateway run
    depends_on:
      - mcp-gateway
    ports:
      - "127.0.0.1:${HERMES_GATEWAY_PORT:-8642}:8642"
      - "127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}:9119"
    volumes:
      - ${HERMES_DATA_DIR:-/home/ubuntu/.hermes}:/opt/data
    environment:
      HERMES_DASHBOARD: "1"
      HERMES_UID: "${HERMES_UID:-1000}"
      HERMES_GID: "${HERMES_GID:-1000}"
      MCP_GATEWAY_URL: "${MCP_GATEWAY_URL:-http://mcp-gateway:8811}"
    shm_size: "1g"
    mem_limit: "4g"
    cpus: "2.0"
    networks:
      - hermes-mcp

networks:
  hermes-mcp:
    name: hermes-mcp
```

If Task 1 proves the Gateway must be launched through the Docker MCP CLI plugin rather than a direct image, replace `mcp-gateway` with a verified containerized CLI-plugin launch path and keep the same security rule: only this service mounts docker.sock.

- [ ] **Step 3: Validate Compose syntax**

Run:

```bash
docker compose config >/tmp/hermes-docker-deployment-compose.yml
```

Expected: exit 0. Inspect generated config:

```bash
rg -n "docker.sock|container_name|restart|init|user:" /tmp/hermes-docker-deployment-compose.yml
```

Expected: docker.sock appears only under `mcp-gateway`; Hermes has `init: true`, `user: root`, and `restart: always`.

- [ ] **Step 4: Commit environment and Compose files**

Run:

```bash
git add .env.example docker-compose.yml
git commit -m "feat: add hermes gateway compose stack"
```

Expected: commit succeeds.

---

### Task 3: Add Install Script

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write `install.sh`**

Add:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "created .env from .env.example"
else
  echo ".env already exists"
fi

if docker ps >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER_COMPOSE=(sudo docker compose)
else
  echo "error: cannot access Docker daemon; run as a docker-enabled user or configure passwordless sudo for docker" >&2
  exit 1
fi

SCRIPTS=(install.sh)
if [ -f run.sh ]; then
  SCRIPTS+=(run.sh)
fi
bash -n "${SCRIPTS[@]}"
"${DOCKER_COMPOSE[@]}" config >/dev/null

echo "hermes-docker-deployment is installed."
echo
echo "First-time Hermes setup:"
echo "  docker run -it --rm \\"
echo "    -v /home/ubuntu/.hermes:/opt/data \\"
echo "    -e HERMES_UID=1000 \\"
echo "    -e HERMES_GID=1000 \\"
echo "    nousresearch/hermes-agent:latest setup"
echo
echo "Then run:"
echo "  ./run.sh"
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x install.sh
```

Expected: command exits 0.

- [ ] **Step 3: Validate script**

Run:

```bash
bash -n install.sh
./install.sh
```

Expected: `bash -n` exits 0; `./install.sh` creates `.env` if absent and validates Compose.

- [ ] **Step 4: Commit install script**

Run:

```bash
git add install.sh .env
git reset -- .env
git add install.sh
git commit -m "feat: add install checks"
```

Expected: only `install.sh` is committed. `.env` remains untracked until `.gitignore` is added in Task 4.

---

### Task 4: Add Run Script

**Files:**
- Create: `run.sh`
- Create or modify: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

Add:

```gitignore
.env
```

- [ ] **Step 2: Write `run.sh`**

Add:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "created .env from .env.example"
fi

set -a
. ./.env
set +a

if docker ps >/dev/null 2>&1; then
  DOCKER=(docker)
  DOCKER_COMPOSE=(docker compose)
elif sudo -n docker ps >/dev/null 2>&1; then
  DOCKER=(sudo docker)
  DOCKER_COMPOSE=(sudo docker compose)
else
  echo "error: cannot access Docker daemon; run as a docker-enabled user or configure passwordless sudo for docker" >&2
  exit 1
fi

"${DOCKER_COMPOSE[@]}" up -d
"${DOCKER_COMPOSE[@]}" ps

HERMES_NAME="${HERMES_CONTAINER_NAME:-hermes}"
GATEWAY_NAME="${MCP_GATEWAY_CONTAINER_NAME:-mcp-gateway}"

"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$HERMES_NAME" | rg '^true$' >/dev/null
"${DOCKER[@]}" inspect -f '{{.State.Running}}' "$GATEWAY_NAME" | rg '^true$' >/dev/null

echo
echo "Hermes and Docker MCP Gateway are running."
echo "Hermes gateway:   http://127.0.0.1:${HERMES_GATEWAY_PORT:-8642}"
echo "Hermes dashboard: http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}"
echo "MCP Gateway:      http://127.0.0.1:${MCP_GATEWAY_PORT:-8811}"
echo
echo "If Hermes MCP registration was not automated during implementation,"
echo "register the Docker MCP Gateway inside Hermes using the verified Hermes CLI command from README.md."
```

If Task 1 proves MCP registration can be safely automated, add the verified noninteractive registration block after container health checks. Keep the script idempotent by removing an existing `docker-gateway` registration before adding it, or by accepting the current registration if Hermes reports it already exists.

- [ ] **Step 3: Make script executable**

Run:

```bash
chmod +x run.sh
```

Expected: command exits 0.

- [ ] **Step 4: Validate run script syntax**

Run:

```bash
bash -n run.sh
```

Expected: exit 0.

- [ ] **Step 5: Commit run script and ignore file**

Run:

```bash
git add .gitignore run.sh
git commit -m "feat: add runtime launcher"
```

Expected: commit succeeds.

---

### Task 5: Add README Documentation

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Add documentation covering:

```markdown
# Hermes Docker Deployment

This repository deploys Hermes with Docker MCP Gateway. It replaces the old `yui-ecosystem` host MCP service approach.

## Architecture

- `hermes` runs `nousresearch/hermes-agent:latest`.
- `mcp-gateway` runs Docker MCP Gateway.
- Hermes does not mount `/var/run/docker.sock`.
- Docker MCP Gateway is the only long-running service with docker.sock access.
- Hermes connects to Gateway as its MCP entry point.

## Install

```bash
./install.sh
```

## First-Time Hermes Setup

```bash
docker run -it --rm \
  -v /home/ubuntu/.hermes:/opt/data \
  -e HERMES_UID=1000 \
  -e HERMES_GID=1000 \
  nousresearch/hermes-agent:latest setup
```

## Run

```bash
./run.sh
```

## Logs

```bash
docker compose logs -f
```

## Stop

```bash
docker compose down
```

## Self-Restart

Inside the Hermes container, run:

```bash
kill 1
```

Compose restarts Hermes because the service uses `init: true`, `user: root`, and `restart: always`.

## Verification

```bash
bash -n install.sh run.sh
docker compose config >/dev/null
docker compose up -d
docker compose ps
docker compose exec hermes sh -lc 'kill 1'
sleep 5
docker compose ps
```

Hermes should restart and return to the running state.
```

Also include the verified Hermes MCP registration command from Task 1.

- [ ] **Step 2: Validate README commands are consistent with files**

Run:

```bash
rg -n "docker.sock|kill 1|docker compose|hermes-agent|yui-ecosystem|mcp-gateway" README.md docker-compose.yml .env.example
```

Expected: output shows the intended architecture and no instruction to mount docker.sock into Hermes.

- [ ] **Step 3: Commit README**

Run:

```bash
git add README.md
git commit -m "docs: add deployment guide"
```

Expected: commit succeeds.

---

### Task 6: Add Migration Documentation

**Files:**
- Create: `docs/migration-from-yui-ecosystem.md`

- [ ] **Step 1: Write migration doc**

Add:

```markdown
# Migration From yui-ecosystem

The old `/home/ubuntu/yui-ecosystem` repository is archived. It remains useful as historical reference, but its host-side MCP service and eco-plugin lifecycle are not part of the new deployment.

## Removed Components

- `scripts/yui_ecosystem.py`
- `scripts/yui-ecosystem`
- `scripts/restart-yui.sh`
- `restart_self`
- `get_restart_status`
- `tail_restart_log`
- `eco_plugin_list`
- `eco_plugin_start`
- `eco_plugin_stop`
- `eco_plugin_install`
- `eco-plugins/*.yaml`

## Mapping

| Old concept | New model |
| --- | --- |
| Host MCP service | Docker MCP Gateway |
| `restart_self` | `kill 1` inside Hermes plus Compose `restart: always` |
| Restart logs | `docker compose logs hermes` |
| Eco-plugin registry | Docker MCP catalog/profile entries |
| Eco-plugin install | Docker MCP Gateway Dynamic MCP or profile server add flow |
| Hermes Docker control | Gateway-managed MCP tools; Hermes has no docker.sock |

## Security Boundary

Hermes must not receive `/var/run/docker.sock`. Docker access belongs to Docker MCP Gateway and any Gateway-managed tools that are explicitly enabled through Docker's catalog/profile mechanism.
```

- [ ] **Step 2: Cross-check migration doc with README**

Run:

```bash
rg -n "restart_self|eco_plugin|docker.sock|archived|Docker MCP Gateway" docs/migration-from-yui-ecosystem.md README.md
```

Expected: migration doc explicitly says old tools are removed and README states the new boundary.

- [ ] **Step 3: Commit migration doc**

Run:

```bash
git add docs/migration-from-yui-ecosystem.md
git commit -m "docs: document yui ecosystem migration"
```

Expected: commit succeeds.

---

### Task 7: End-to-End Verification

**Files:**
- Modify docs or scripts only if verification reveals mismatches.

- [ ] **Step 1: Run static checks**

Run:

```bash
bash -n install.sh run.sh
docker compose config >/dev/null
```

Expected: all commands exit 0.

- [ ] **Step 2: Start stack**

Run:

```bash
./run.sh
```

Expected: Compose starts `hermes` and `mcp-gateway`; `docker compose ps` shows both services running.

- [ ] **Step 3: Verify docker.sock boundary**

Run:

```bash
docker inspect hermes --format '{{json .Mounts}}' | rg -v 'docker.sock'
docker inspect mcp-gateway --format '{{json .Mounts}}' | rg 'docker.sock'
```

Expected: Hermes inspect output does not contain `docker.sock`; mcp-gateway inspect output contains `docker.sock`.

- [ ] **Step 4: Verify Hermes self-restart**

Run:

```bash
before="$(docker inspect hermes --format '{{.State.StartedAt}}')"
docker exec hermes sh -lc 'kill 1' || true
sleep 8
after="$(docker inspect hermes --format '{{.State.StartedAt}}')"
test "$before" != "$after"
docker inspect hermes --format '{{.State.Running}}' | rg '^true$' >/dev/null
```

Expected: `StartedAt` changes and Hermes is running.

- [ ] **Step 5: Verify Gateway registration path**

Run the verified Hermes MCP registration command from Task 1, or confirm README prints the exact manual command if automation is unsupported.

Expected: Hermes accepts the Docker MCP Gateway configuration, or README accurately documents the manual command and current blocker.

- [ ] **Step 6: Check git status**

Run:

```bash
git status --short
```

Expected: no unexpected untracked files except local `.env`, which is ignored.

- [ ] **Step 7: Final verification commit if fixes were needed**

If verification required changes:

```bash
git add .env.example docker-compose.yml install.sh run.sh README.md docs/migration-from-yui-ecosystem.md docs/superpowers/specs/2026-05-13-hermes-docker-deployment-design.md
git commit -m "fix: align deployment with verified gateway behavior"
```

Expected: commit succeeds only if files changed.
