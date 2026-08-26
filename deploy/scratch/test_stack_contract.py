import ast
from pathlib import Path
import unittest

import yaml


STACK = Path(__file__).with_name("stack.yaml")


def gateway_auth_source():
    documents = yaml.safe_load_all(STACK.read_text(encoding="utf-8"))
    settings = next(
        document
        for document in documents
        if document
        and document.get("kind") == "ConfigMap"
        and document.get("metadata", {}).get("name") == "awx-controller-settings"
    )
    return settings["data"]["gateway_auth.py"]


class GatewayAuthenticationContractTest(unittest.TestCase):
    def test_authenticated_gateway_user_is_attributed_without_model_save(self):
        source = gateway_auth_source()
        tree = ast.parse(source, filename="gateway_auth.py")
        authenticate = next(
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.FunctionDef) and node.name == "authenticate"
        )
        calls = [
            node.func.id
            for node in ast.walk(authenticate)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        ]

        self.assertIn("set_current_user", calls)
        self.assertIn("User.objects.filter(pk=user.pk).update(**updates)", source)
        self.assertNotIn("user.save(", source)


if __name__ == "__main__":
    unittest.main()
