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

    def test_alex_trivial_route_is_teo_with_engine_verification(self):
        # Pedido trivial: Alex → Teo; verifica el motor con el comando del
        # proyecto (Jhon si no hay). La autorización es skalling_workflow.
        source = (ROOT / "agents-base" / "Alex.md").read_text(encoding="utf-8")
        self.assertIn("## Una sola autoridad: `skalling_workflow`", source)
        self.assertIn("**Alex → Teo**", source)
        self.assertIn('action: "start"', source)
        self.assertIn("id del workflow", source)
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

    def test_microchange_contract_does_not_reintroduce_planning_chain(self):
        teo = (ROOT / "agents-base" / "Teo.md").read_text(encoding="utf-8")
        alex = (ROOT / "agents-base" / "Alex.md").read_text(encoding="utf-8")
        self.assertIn("### Microcambio — carril mínimo", teo)
        self.assertIn("No convoco Pol, Sol, Luz ni Pau", teo)
        self.assertIn("### Modo staged — plan de Sol", teo)
        self.assertIn("No se activa por la etiqueta `medium/high` por sí sola", teo)
        self.assertIn("no creo plan y no delego a Pol/Sol/Pau", alex)

    def test_handoff_contract_matches_the_payload_teo_receives(self):
        handoff = (ROOT / ".opencode/skills/skalling-handoff/SKILL.md").read_text(encoding="utf-8")
        teo = (ROOT / "agents-base/Teo.md").read_text(encoding="utf-8")
        for field in ("readiness", "implementation_allowed", "route", "request_context"):
            self.assertIn(f'"{field}"', teo)
        self.assertIn("En un microcambio focused", handoff)


if __name__ == "__main__":
    unittest.main()
