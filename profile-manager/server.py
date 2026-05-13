#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
import json
import os
import re
import subprocess
import sys
from typing import Any, Callable


SERVER_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
PROTECTED_SERVERS = {"profile-manager"}


class ProfileManagerError(ValueError):
    def __init__(self, message: str, code: int = -32602) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


Runner = Callable[[list[str]], CommandResult]


def run_docker_mcp(args: list[str]) -> CommandResult:
    command = [os.environ.get("DOCKER_MCP_BIN", "/usr/local/bin/docker-mcp"), *args]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    return CommandResult(result.returncode, result.stdout, result.stderr)


class ProfileManager:
    def __init__(
        self,
        profile_id: str,
        catalog_ref: str,
        allowed_servers: set[str],
        runner: Runner = run_docker_mcp,
    ) -> None:
        self.profile_id = profile_id
        self.catalog_ref = catalog_ref
        self.allowed_servers = allowed_servers
        self.runner = runner

    @classmethod
    def from_env(cls) -> "ProfileManager":
        allowed = {
            item.strip()
            for item in os.environ.get("ALLOWED_SERVERS", "*").split(",")
            if item.strip()
        }
        return cls(
            profile_id=os.environ.get("PROFILE_ID", "hermes-default"),
            catalog_ref=os.environ.get("CATALOG_REF", "mcp/docker-mcp-catalog:latest"),
            allowed_servers=allowed,
        )

    def profile_list(self) -> dict[str, str]:
        return self._run(["profile", "list"])

    def profile_show(self) -> dict[str, str]:
        return self._run(["profile", "show", self.profile_id, "--format", "yaml"])

    def profile_server_add(self, server: str) -> dict[str, str]:
        ref = self.catalog_server_ref(server)
        result = self._run(["profile", "server", "add", self.profile_id, "--server", ref])
        return {"profile": self.profile_id, "server": server, "ref": ref, **result}

    def profile_server_remove(self, server: str) -> dict[str, str]:
        safe = self.validate_server_name(server)
        if safe in PROTECTED_SERVERS:
            raise ProfileManagerError(f"server is protected and cannot be removed: {safe}")
        if not self.is_allowed(safe):
            raise ProfileManagerError(f"server is not allowed: {safe}")
        result = self._run(["profile", "server", "remove", self.profile_id, safe])
        return {"profile": self.profile_id, "server": safe, **result}

    def catalog_list(self) -> dict[str, str]:
        return self._run(["catalog", "list"])

    def catalog_pull_official(self) -> dict[str, str]:
        return self._run(["catalog", "pull", self.catalog_ref])

    def catalog_server_ref(self, server: str) -> str:
        safe = self.validate_server_name(server)
        if not self.is_allowed(safe):
            raise ProfileManagerError(f"server is not allowed: {safe}")
        return f"catalog://{self.catalog_ref}/{safe}"

    def is_allowed(self, server: str) -> bool:
        return "*" in self.allowed_servers or server in self.allowed_servers

    def validate_server_name(self, server: str) -> str:
        if not isinstance(server, str) or not SERVER_NAME_PATTERN.fullmatch(server):
            raise ProfileManagerError(f"invalid server name: {server!r}")
        return server

    def _run(self, args: list[str]) -> dict[str, str]:
        result = self.runner(args)
        if result.returncode != 0:
            raise ProfileManagerError(
                result.stderr.strip() or result.stdout.strip() or "docker mcp command failed",
                -32000,
            )
        return {"stdout": result.stdout.strip(), "stderr": result.stderr.strip()}


class McpServer:
    def __init__(self, manager: ProfileManager) -> None:
        self.manager = manager

    def handle(self, message: Any) -> dict[str, Any] | None:
        if not isinstance(message, dict):
            return self._error(None, -32600, "JSON-RPC request must be an object")

        method = message.get("method")
        message_id = message.get("id")
        try:
            if method == "initialize":
                return self._result(
                    message_id,
                    {
                        "protocolVersion": message.get("params", {}).get("protocolVersion", "2024-11-05"),
                        "serverInfo": {"name": "profile-manager", "version": "0.1.0"},
                        "capabilities": {"tools": {}},
                    },
                )
            if method == "tools/list":
                return self._result(message_id, {"tools": self._tools()})
            if method == "tools/call":
                params = message.get("params", {})
                if not isinstance(params, dict):
                    raise ProfileManagerError("tools/call params must be an object")
                arguments = params.get("arguments", {})
                if not isinstance(arguments, dict):
                    raise ProfileManagerError("tools/call arguments must be an object")
                return self._result(message_id, self._content(self._call_tool(params.get("name"), arguments)))
            if message_id is not None:
                return self._error(message_id, -32601, f"unknown method: {method}")
            return None
        except ProfileManagerError as error:
            return self._error(message_id, error.code, str(error))

    def _call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name == "profile_list":
            return self.manager.profile_list()
        if name == "profile_show":
            return self.manager.profile_show()
        if name == "profile_server_add":
            return self.manager.profile_server_add(self._server_arg(arguments))
        if name == "profile_server_remove":
            return self.manager.profile_server_remove(self._server_arg(arguments))
        if name == "catalog_list":
            return self.manager.catalog_list()
        if name == "catalog_pull_official":
            return self.manager.catalog_pull_official()
        raise ProfileManagerError(f"unknown tool: {name}")

    def _server_arg(self, arguments: dict[str, Any]) -> str:
        server = arguments.get("server")
        if not isinstance(server, str) or not server:
            raise ProfileManagerError("tool requires non-empty string argument: server")
        return server

    def _tools(self) -> list[dict[str, Any]]:
        server_schema = {
            "type": "object",
            "properties": {"server": {"type": "string", "description": "Allowed short server name, such as fetch."}},
            "required": ["server"],
        }
        empty_schema = {"type": "object", "properties": {}}
        return [
            {"name": "profile_list", "description": "List Docker MCP profiles.", "inputSchema": empty_schema},
            {"name": "profile_show", "description": "Show the managed Docker MCP profile.", "inputSchema": empty_schema},
            {"name": "profile_server_add", "description": "Add a configured catalog server to the managed profile.", "inputSchema": server_schema},
            {"name": "profile_server_remove", "description": "Remove a configured catalog server from the managed profile.", "inputSchema": server_schema},
            {"name": "catalog_list", "description": "List Docker MCP catalogs available to the gateway.", "inputSchema": empty_schema},
            {"name": "catalog_pull_official", "description": "Pull the configured official Docker MCP catalog.", "inputSchema": empty_schema},
        ]

    def _content(self, value: Any) -> dict[str, Any]:
        return {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False, indent=2)}]}

    def _result(self, message_id: Any, result: Any) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": message_id, "result": result}

    def _error(self, message_id: Any, code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": message}}


def read_message() -> tuple[dict[str, Any], str] | None:
    headers: dict[str, str] = {}
    line = sys.stdin.buffer.readline()
    if not line:
        return None
    if line.lstrip().startswith(b"{"):
        return json.loads(line.decode("utf-8")), "jsonl"

    while True:
        if line in {b"\r\n", b"\n"}:
            break
        key, _, value = line.decode("ascii").partition(":")
        headers[key.lower()] = value.strip()
        line = sys.stdin.buffer.readline()
        if not line:
            return None

    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8")), "headers"


def write_message(message: dict[str, Any], mode: str) -> None:
    data = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if mode == "jsonl":
        sys.stdout.buffer.write(data + b"\n")
        sys.stdout.buffer.flush()
        return
    sys.stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main() -> int:
    server = McpServer(ProfileManager.from_env())
    while True:
        item = read_message()
        if item is None:
            return 0
        message, mode = item
        response = server.handle(message)
        if response is not None:
            write_message(response, mode)


if __name__ == "__main__":
    raise SystemExit(main())
