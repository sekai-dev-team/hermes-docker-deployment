# Hermes Docker Deployment Design

Date: 2026-05-13

## Goal

Create a new deployment repository at `/home/ubuntu/hermes-docker-deployment` for running Hermes with Docker MCP Gateway. This repository replaces the old `yui-ecosystem` deployment approach. The old `/home/ubuntu/yui-ecosystem` repository is treated as archived reference material, not as code to evolve.

## Scope

The first version is a minimal deployment repository plus migration documentation.

It includes:

- Docker Compose deployment for exactly two long-running services: `hermes` and `mcp-gateway`.
- Install and run scripts for local host setup.
- Environment examples for ports, image names, data paths, and Gateway connection settings.
- README documentation for setup, operation, restart, and verification.
- Migration documentation that maps old `yui-ecosystem` concepts to the new Docker MCP Gateway design.

It does not include:

- The old `yui-ecosystem` host MCP service.
- Python MCP server code from `scripts/yui_ecosystem.py`.
- `restart_self`, `get_restart_status`, or `tail_restart_log`.
- `eco_plugin_list`, `eco_plugin_start`, `eco_plugin_stop`, or `eco_plugin_install`.
- `eco-plugins/*.yaml` as a local plugin registry.
- Host-side restart scripts such as `restart-yui.sh`.
- Hermes source mounting or `uv pip install --system -e .`.
- A custom Docker Management MCP Server in the first version.
- Custom catalog maintenance automation in the first version.

## Architecture

The deployment contains two core containers:

1. `mcp-gateway`
   - Runs Docker MCP Gateway.
   - Owns access to `/var/run/docker.sock`.
   - Manages MCP server containers through Docker's Gateway and catalog/profile model.
   - Exposes one MCP endpoint for Hermes.

2. `hermes`
   - Runs `nousresearch/hermes-agent:latest` by default.
   - Mounts `/home/ubuntu/.hermes` as the persistent Hermes data directory.
   - Connects to `mcp-gateway` as its MCP entry point.
   - Does not mount `/var/run/docker.sock`.
   - Uses Docker Compose restart behavior for self-restart.

Hermes self-restart is handled by:

- `init: true`, so Docker injects an init process as PID 1.
- `restart: always`, so Compose restarts the container after it exits.
- Agent command terminates the non-root Hermes gateway process; Compose brings the container back.

This keeps Docker control out of the Hermes container. Docker access is delegated to Gateway-managed MCP tools instead.

## Deployment Files

The repository should contain:

- `.env.example`
  - `HERMES_IMAGE=nousresearch/hermes-agent:latest`
  - `HERMES_CONTAINER_NAME=hermes`
  - `HERMES_DATA_DIR=/home/ubuntu/.hermes`
  - `HERMES_GATEWAY_PORT=8642`
  - `HERMES_DASHBOARD_PORT=9119`
  - `MCP_GATEWAY_PORT=8811`
  - Gateway transport and endpoint values after implementation verification.

- `docker-compose.yml`
  - Defines `hermes` and `mcp-gateway`.
  - Uses a shared Docker network.
  - Binds Hermes UI/API ports to `127.0.0.1`.
  - Gives docker.sock only to `mcp-gateway`.
  - Configures Hermes restart with `init: true` and `restart: always`.

- `install.sh`
  - Creates `.env` from `.env.example` when missing.
  - Checks Docker and Docker Compose access.
  - Validates shell scripts.
  - Validates Compose configuration.
  - Prints first-time Hermes setup instructions.

- `run.sh`
  - Creates `.env` if needed.
  - Starts the Compose stack.
  - Verifies the expected containers are running.
  - Registers or prints the command to register Docker MCP Gateway in Hermes, depending on what the current Hermes CLI supports.

- `README.md`
  - Explains the new architecture and why `yui-ecosystem` is archived.
  - Documents install, first-time setup, run, stop, logs, and verification.
  - Documents non-root Hermes process self-restart.
  - Documents that Hermes must not receive docker.sock.

- `docs/migration-from-yui-ecosystem.md`
  - Maps old `yui-ecosystem` concepts to the new model.
  - Explicitly lists removed tools and scripts.
  - Explains that eco-plugin discovery/installation moves to Docker MCP Gateway catalog/profile/Dynamic MCP behavior.

## Command-Level Verification Required During Implementation

The architecture is fixed, but two command-level details must be verified on the target machine before scripts and docs are finalized.

### Docker MCP Gateway startup

The local design document at `/home/ubuntu/.hermes/yui-ecosystem-doc/docker-mcp-gateway-deployment.md` shows an image-style deployment using `docker/mcp-gateway:latest` and SSE transport. Current Docker documentation emphasizes the `docker mcp gateway run` CLI flow with HTTP transport options such as `streaming`.

Implementation must verify which startup mode works on this host:

- Whether a supported Gateway container image is available and suitable for Compose.
- Whether Gateway should expose `sse` or `streaming` transport.
- Which port and endpoint path Hermes must use.

The final Compose file must be based on a successfully validated startup path, not only on remembered or draft documentation.

### Hermes MCP registration

The old `yui-ecosystem` scripts used Hermes CLI commands similar to `hermes mcp add <name> --url <url>`. The new repository must verify the current official Hermes image behavior:

- Where the Hermes CLI binary lives inside the container.
- Whether `hermes mcp add` supports the Gateway transport mode.
- Which URL format is accepted for Docker MCP Gateway.
- Whether registration can be automated safely or should be printed for manual execution.

The final `run.sh` and README must match the verified CLI behavior.

## Migration From yui-ecosystem

Old to new mapping:

| Old yui-ecosystem concept | New design |
| --- | --- |
| Host-side MCP service on port 8766 | Docker MCP Gateway |
| `restart_self` | Terminate the non-root Hermes gateway process plus Compose `restart: always` |
| `get_restart_status` and `tail_restart_log` | `docker compose ps` and `docker compose logs` |
| `eco_plugin_install` | Docker MCP Gateway catalog/profile/Dynamic MCP server add flow |
| `eco_plugin_start` and `eco_plugin_stop` | Gateway-managed MCP server lifecycle, with optional future Docker management MCP tools |
| `eco-plugins/*.yaml` | Docker MCP catalog entries |
| Hermes with host-side Docker management MCP | Hermes connected only to Docker MCP Gateway |

## Success Criteria

After implementation:

- A fresh checkout of `/home/ubuntu/hermes-docker-deployment` can create `.env`, validate Docker Compose, and start Hermes plus Docker MCP Gateway.
- Hermes runs from the official `nousresearch/hermes-agent:latest` image.
- Hermes has no docker.sock mount.
- Docker MCP Gateway is the only long-running service with docker.sock access.
- `docker compose config` succeeds.
- `docker compose up -d` starts both services.
- Hermes can be configured to talk to Docker MCP Gateway.
- terminating the non-root Hermes gateway process causes Compose to restart Hermes.
- Documentation clearly states that `/home/ubuntu/yui-ecosystem` is archived and its MCP service/tools are deprecated.

## Open Risks

- Docker MCP Gateway packaging may require using the Docker CLI plugin rather than a direct container image. The implementation must choose the validated host-compatible path.
- Hermes CLI MCP registration may not support fully noninteractive Gateway registration. If so, the deployment should print exact manual commands instead of pretending automation works.
- Docker MCP Dynamic MCP behavior is documented as experimental by Docker. The first version should rely on the Gateway as the aggregation point and keep custom catalog automation out of scope.
