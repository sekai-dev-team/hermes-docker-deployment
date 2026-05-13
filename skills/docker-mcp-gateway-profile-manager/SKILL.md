---
name: docker-mcp-gateway-profile-manager
description: Use when managing Docker MCP Gateway, Docker MCP catalogs, persistent profiles, profile-manager tools, or installing/removing Docker MCP servers in the Hermes Docker deployment.
---

# Docker MCP Gateway Profile Manager

Use this skill when the user asks about Docker MCP Gateway tools, catalogs, profiles, persistent MCP server installation, or why newly installed MCP tools are not visible yet.

## Mental Model

- Catalog: the server directory. It answers "what MCP servers exist?"
- Profile: the persistent enabled-server list. It answers "what should Gateway load at startup?"
- MCP server: the container/service that provides actual tools, such as `fetch`.
- Docker MCP Gateway: the single MCP endpoint Hermes connects to. It reads the active profile, starts the selected MCP servers, merges their tool schemas, and exposes them to Hermes.
- Profile manager: a restricted MCP server loaded by Gateway. It edits the managed profile without giving Hermes direct Docker socket access.

## Safety Boundary

Prefer `profile_*` tools for persistent installs. They only accept short catalog server names such as `fetch` or `aks`.

Do not ask for or pass full refs such as `docker://...`, `file://...`, arbitrary images, paths, volumes, or environment variables. The profile manager builds fixed official-catalog refs internally.

The deployment may allow `PROFILE_MANAGER_ALLOWED_SERVERS=*`. This means "any valid short server name from the configured catalog", not arbitrary Docker images or local files.

Do not remove `profile-manager` from the persistent profile. It is the protected management channel.

## Tool Groups

Persistent management tools:

- `catalog_list`: show pulled catalogs.
- `catalog_pull_official`: pull or refresh the configured official catalog.
- `profile_list`: list profiles.
- `profile_show`: show the managed profile and enabled servers.
- `profile_server_add`: add a short-name server to the persistent profile.
- `profile_server_remove`: remove a short-name server from the persistent profile.

Dynamic Gateway tools:

- `mcp_find`: search the catalog.
- `mcp_add`: dynamically add a server to the current Gateway session.
- `mcp_config_set`: configure a dynamically loaded server.
- `mcp_remove`: remove a dynamic server from the current Gateway session.
- `mcp_exec`: execute a tool from a dynamically loaded server.
- `mcp_create_profile` and `mcp_activate_profile`: Gateway-native profile operations. Prefer the restricted `profile_*` tools unless the user explicitly wants the Gateway-native flow.

Other Gateway tools:

- `fetch`: native tool from the persistent `fetch` MCP server, if installed.
- `code_mode`: JavaScript sandbox for combining MCP calls.
- `list_prompts`, `get_prompt`, `list_resources`, `read_resource`: inspect prompts/resources exposed by MCP servers.

## Persistent Install Workflow

1. Search:
   - Use `mcp_find` for likely server names.
2. Inspect:
   - Use `profile_show` to see what is already persistent.
3. Install:
   - Use `profile_server_add` with a short server name, for example `server="fetch"`.
4. Confirm:
   - Use `profile_show` again.
5. Refresh visibility:
   - Gateway runs with `--watch`, so profile changes may reload automatically.
   - Tool schema in the current Hermes/Yui run may not refresh immediately.
   - If the new native tools are not visible, ask the user to restart Gateway and start a new Hermes/Yui run. For a stronger refresh, restart Hermes gateway too.

## Dynamic Exploration Workflow

Use dynamic tools when trying something temporarily:

1. `mcp_find` to discover a server.
2. `mcp_add` to load it into the current Gateway session.
3. `mcp_config_set` if it needs configuration.
4. `mcp_exec` to call its tools.
5. If the server is useful long-term, install it with `profile_server_add` so it survives restart.

## Troubleshooting

If only Gateway meta tools are visible, check in order:

1. `catalog_list` shows `mcp/docker-mcp-catalog:latest`.
2. `profile_show` includes `profile-manager` and the expected server.
3. Gateway has reloaded after the profile change.
4. Hermes/Yui started a new run after Gateway reloaded, so the prompt contains the new tool schema.

If `profile_server_add` fails, report the exact error. Common causes are an invalid short name, a server missing from the catalog, or a catalog that has not been pulled.
