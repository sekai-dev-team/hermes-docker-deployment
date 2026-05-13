import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
import io


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "profile-manager"))

import server


class ProfileManagerSecurityTest(unittest.TestCase):
    def setUp(self):
        self.manager = server.ProfileManager(
            profile_id="hermes-default",
            catalog_ref="mcp/docker-mcp-catalog:latest",
            allowed_servers={"fetch", "github"},
            runner=lambda args: server.CommandResult(0, "ok", ""),
        )

    def test_allowed_server_ref_is_built_from_short_name(self):
        self.assertEqual(
            self.manager.catalog_server_ref("fetch"),
            "catalog://mcp/docker-mcp-catalog:latest/fetch",
        )

    def test_rejects_non_allowlisted_server(self):
        with self.assertRaisesRegex(server.ProfileManagerError, "not allowed"):
            self.manager.catalog_server_ref("sqlite")

    def test_rejects_docker_ref_instead_of_short_name(self):
        with self.assertRaises(server.ProfileManagerError):
            self.manager.catalog_server_ref("docker://evil/image:latest")

    def test_rejects_path_like_name(self):
        with self.assertRaises(server.ProfileManagerError):
            self.manager.catalog_server_ref("../fetch")

    def test_profile_add_uses_fixed_profile_and_catalog_ref(self):
        calls = []

        def runner(args):
            calls.append(args)
            return server.CommandResult(0, "added", "")

        manager = server.ProfileManager(
            profile_id="hermes-default",
            catalog_ref="mcp/docker-mcp-catalog:latest",
            allowed_servers={"fetch"},
            runner=runner,
        )

        result = manager.profile_server_add("fetch")

        self.assertEqual(result["server"], "fetch")
        self.assertEqual(
            calls,
            [
                [
                    "profile",
                    "server",
                    "add",
                    "hermes-default",
                    "--server",
                    "catalog://mcp/docker-mcp-catalog:latest/fetch",
                ]
            ],
        )

    def test_json_rpc_tools_list_contains_only_safe_tools(self):
        response = server.McpServer(self.manager).handle(
            {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        )
        names = [tool["name"] for tool in response["result"]["tools"]]

        self.assertEqual(
            names,
            [
                "profile_list",
                "profile_show",
                "profile_server_add",
                "profile_server_remove",
                "catalog_list",
                "catalog_pull_official",
            ],
        )

    def test_json_rpc_rejects_unknown_tool(self):
        response = server.McpServer(self.manager).handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {"name": "docker_run", "arguments": {}},
            }
        )

        self.assertEqual(response["error"]["code"], -32602)

    def test_tool_response_is_text_json(self):
        response = server.McpServer(self.manager).handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {"name": "profile_server_add", "arguments": {"server": "fetch"}},
            }
        )

        content = response["result"]["content"][0]
        self.assertEqual(content["type"], "text")
        self.assertEqual(json.loads(content["text"])["server"], "fetch")

    def test_stdio_supports_json_lines(self):
        payload = b'{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n'
        stdin = type("FakeStdin", (), {"buffer": io.BytesIO(payload)})()

        with patch.object(server.sys, "stdin", stdin):
            message, mode = server.read_message()

        self.assertEqual(mode, "jsonl")
        self.assertEqual(message["method"], "tools/list")

    def test_stdio_writes_json_lines(self):
        stdout = type("FakeStdout", (), {"buffer": io.BytesIO()})()

        with patch.object(server.sys, "stdout", stdout):
            server.write_message({"jsonrpc": "2.0", "id": 1, "result": {}}, "jsonl")

        self.assertTrue(stdout.buffer.getvalue().endswith(b"\n"))
        self.assertNotIn(b"Content-Length", stdout.buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
