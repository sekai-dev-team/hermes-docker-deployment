import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DeploymentScriptsTest(unittest.TestCase):
    def test_one_command_deploy_runs_real_smoke_test(self):
        deploy = ROOT / "deploy.sh"

        self.assertTrue(deploy.exists())
        self.assertIn("./run.sh", deploy.read_text(encoding="utf-8"))
        self.assertIn("./scripts/real-smoke-test.sh", deploy.read_text(encoding="utf-8"))

    def test_real_smoke_test_exercises_inner_docker_gateway_and_ask_yui(self):
        script = ROOT / "scripts" / "real-smoke-test.sh"

        self.assertTrue(script.exists())
        body = script.read_text(encoding="utf-8")
        self.assertIn("docker -H tcp://127.0.0.1:2375", body)
        self.assertIn("mcp-gateway", body)
        self.assertIn("profile-manager", body)
        self.assertIn("scripts/ask-yui.sh", body)
        self.assertIn("HERMES_DOCKER_DEPLOYMENT_REAL_TEST_OK", body)

    def test_ask_yui_targets_hermes_container(self):
        script = ROOT / "scripts" / "ask-yui.sh"

        self.assertTrue(script.exists())
        body = script.read_text(encoding="utf-8")
        self.assertIn("${HERMES_CONTAINER_NAME:-hermes}", body)
        self.assertIn("/opt/hermes/.venv/bin/hermes", body)
        self.assertIn("-z", body)


if __name__ == "__main__":
    unittest.main()
