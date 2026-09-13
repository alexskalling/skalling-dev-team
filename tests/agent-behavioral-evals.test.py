#!/usr/bin/env python3
"""Evaluaciones conductuales de las siete fases, sin depender de un LLM."""
import json
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def fm(name):
    return yaml.safe_load((ROOT / "agents-base" / f"{name}.md").read_text().split("---", 2)[1])


class BehavioralEvals(unittest.TestCase):
    def test_routine_observation_and_installed_tests_advance_without_prompt(self):
        for name in ("Teo", "Jhon", "Luz"):
            bash = fm(name)["permission"]["bash"]
            self.assertEqual(bash.get("git -C * diff *"), "allow")
            self.assertEqual(bash.get("bash tests/*.test.sh *"), "allow")

    def test_material_actions_stay_behind_authorization(self):
        project = json.loads((ROOT / "templates/opencode.json").read_text())["permission"]["bash"]
        for command in ("git push *", "git reset *"):
            self.assertEqual(project.get(command), "ask")
        for name in ("Teo", "Jhon", "Luz"):
            self.assertEqual(fm(name)["permission"]["teamdb_destructive"], "ask")

    def test_role_separation_is_enforced_by_configuration_and_transition_helper(self):
        self.assertEqual(fm("Jhon")["permission"]["edit"], "deny")
        self.assertEqual(fm("Luz")["permission"]["edit"], "deny")
        helper = (ROOT / "scripts" / "teamdb-claim.sh").read_text()
        self.assertIn("actor != 'jhon'", helper)
        self.assertIn("actor != 'pau'", helper)
        self.assertIn("verificador distinto al implementador", helper)

    def test_advice_and_anti_stall_protocol_is_loaded_from_the_constitution(self):
        text = (ROOT / "constitution" / "constitucion.md").read_text()
        for item in ("Ciclo de resolución y asesoramiento", "Presupuesto de preguntas", "Después de tres intentos"):
            self.assertIn(item, text)


if __name__ == "__main__":
    unittest.main()
