# Migration From yui-ecosystem

The old `/home/ubuntu/yui-ecosystem` tree is an archived reference only. It is useful for historical comparison, but it is not part of this deployment path.

The host-side MCP service and eco-plugin lifecycle from `yui-ecosystem` are intentionally not part of the new deployment. Hermes now runs as a Docker Compose service and reaches Docker-related MCP capability through Docker MCP Gateway.

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

## Migration Map

| Old yui-ecosystem component | New deployment path |
| --- | --- |
| Host MCP service | Docker MCP Gateway |
| `restart_self` | `kill 1` inside Hermes plus Compose `restart: always` |
| Restart logs | `docker compose logs hermes` |
| Eco-plugin registry | Docker MCP catalog/profile entries |
| Eco-plugin install | Docker MCP Gateway Dynamic MCP or profile server add flow |
| Hermes Docker control | Gateway-managed MCP tools; Hermes has no `docker.sock` |

## Security Boundary

Hermes must not receive `/var/run/docker.sock`. Direct Docker access belongs to Docker MCP Gateway and to explicitly enabled Gateway-managed tools.

Keep Hermes on the compose network and register Docker MCP Gateway as the MCP endpoint. Do not reintroduce host-side Docker socket mounts into the Hermes service as a shortcut for Docker control.
