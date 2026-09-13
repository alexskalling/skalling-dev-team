#!/usr/bin/env python3
"""Contratos conductuales: autonomía acotada, orden e independencia."""
import json
from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
AGENTS = ("Alex", "Jes", "Pol", "Sol", "Teo", "Jhon", "Luz", "Pau")


def frontmatter(path):
    return yaml.safe_load(path.read_text(encoding="utf-8").split("---", 2)[1])


class AgentAutonomyContract(unittest.TestCase):
    def test_every_agent_uses_the_shared_autonomy_contract(self):
        for name in AGENTS:
            source = (ROOT / "agents-base" / f"{name}.md").read_text(encoding="utf-8")
            self.assertIn("@include-snippet autonomy-and-authority", source, name)

    def test_verifier_has_an_independent_oracle_before_the_implementation_narrative(self):
        source = (ROOT / "agents-base" / "Jhon.md").read_text(encoding="utf-8")
        self.assertIn("oráculo independiente", source)
        self.assertIn("No recibo la conclusión de Teo", source)

    def test_technical_roles_can_read_public_documentation_without_a_permission_prompt(self):
        for name in ("Teo", "Jhon", "Luz"):
            permissions = frontmatter(ROOT / "agents-base" / f"{name}.md")["permission"]
            self.assertEqual(permissions["webfetch"], "allow", name)

    def test_project_permissions_allow_safe_git_variants_and_bash_test_suites(self):
        permissions = json.loads((ROOT / "templates" / "opencode.json").read_text(encoding="utf-8"))["permission"]
        bash = permissions["bash"]
        policy = yaml.safe_load((ROOT / "data" / "agent-permissions.yaml").read_text(encoding="utf-8"))
        for command in policy["shared_safe_bash"]:
            self.assertEqual(bash.get(command), "allow", command)
        for command in policy["critical_bash"]:
            self.assertEqual(bash.get(command), "ask", command)

    def test_engineering_roles_match_the_safe_project_permissions(self):
        policy = yaml.safe_load((ROOT / "data" / "agent-permissions.yaml").read_text(encoding="utf-8"))
        for name in ("Teo", "Jhon", "Luz"):
            bash = frontmatter(ROOT / "agents-base" / f"{name}.md")["permission"]["bash"]
            for command in policy["shared_safe_bash"]:
                self.assertEqual(bash.get(command), "allow", f"{name}: {command}")

    def test_alex_has_a_direct_lane_that_preserves_teo_then_jhon(self):
        source = (ROOT / "agents-base" / "Alex.md").read_text(encoding="utf-8")
        self.assertIn("## Carril directo", source)
        self.assertIn("Teo → Jhon", source)
        self.assertIn("sin cargar cápsula ni crear plan", source)
        bash = frontmatter(ROOT / "agents-base" / "Alex.md")["permission"]["bash"]
        self.assertEqual(bash.get("git -C * diff *"), "allow")

    def test_constitution_defines_authority_order_and_unblocking_protocol(self):
        constitution = (ROOT / "constitution" / "constitucion.md").read_text(encoding="utf-8")
        for marker in (
            "Propiedad exclusiva de responsabilidades",
            "libertad dentro del carril",
            "Observar → Formular hipótesis → Buscar evidencia",
            "Presupuesto de preguntas",
            "Situación:",
            "Recomendación:",
        ):
            self.assertIn(marker, constitution)


if __name__ == "__main__":
    unittest.main()
