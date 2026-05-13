# Hermes Docker Deployment

Deployment wrapper for the official Hermes agent container with Docker MCP access routed through Docker MCP Gateway. This repo replaces the archived `yui-ecosystem` deployment path at a high level; detailed migration notes belong in the migration doc.

## Architecture

- Hermes runs from the official image `nousresearch/hermes-agent:latest`.
- Docker MCP Gateway runs from `docker/mcp-gateway:latest`.
- Hermes does not mount `/var/run/docker.sock`.
- Docker MCP Gateway is the only service that holds `/var/run/docker.sock`.
- Hermes connects to Docker MCP Gateway over the compose network at `http://mcp-gateway:8811/mcp`.
- Docker MCP Gateway starts with `--port=8811 --transport=streaming`.
- Published ports bind to `127.0.0.1` by default.

## Install

```sh
./install.sh
```

## First-Time Hermes Setup

Run setup once before starting the compose deployment:

```sh
docker run -it --rm -v /home/ubuntu/.hermes:/opt/data -e HERMES_UID=1000 -e HERMES_GID=1000 nousresearch/hermes-agent:latest setup
```

## Run

```sh
./run.sh
```

## Register Docker MCP Gateway

After the containers are running, register Docker MCP Gateway inside Hermes:

```sh
docker exec --user "${HERMES_UID:-1000}:${HERMES_GID:-1000}" -it "${HERMES_CONTAINER_NAME:-hermes}" sh -lc "cd /opt/hermes && /opt/hermes/.venv/bin/hermes mcp add docker-gateway --url 'http://mcp-gateway:8811/mcp'"
```

The Hermes CLI path inside the container is `/opt/hermes/.venv/bin/hermes`.

## Logs

```sh
docker compose logs -f
```

## Stop

```sh
docker compose down
```

## Self-Restart Hermes

To restart Hermes from inside the running container, terminate PID 1:

```sh
docker compose exec hermes sh -lc 'kill 1'
```

The compose service is configured with `init: true`, `user: root`, and `restart: always`, so Docker Compose starts the Hermes container again.

## Verification

```sh
for script in install.sh run.sh; do bash -n "$script"; done
docker compose config >/dev/null
docker compose up -d
docker compose ps
docker compose exec hermes sh -lc 'kill 1'
sleep 8
docker compose ps
```
