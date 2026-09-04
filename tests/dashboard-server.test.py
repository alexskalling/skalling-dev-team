#!/usr/bin/env python3
"""Behavior contract for the TeamDB operations dashboard."""

import importlib.util
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "dashboard_server", ROOT / "scripts" / "dashboard-server.py"
)
dashboard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dashboard)


SCHEMA = """
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE plans (
  id INTEGER PRIMARY KEY, slug TEXT, title TEXT, status TEXT, agent TEXT,
  created_at TEXT, updated_at TEXT, completed_at TEXT
);
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY, plan_id INTEGER, slug TEXT, title TEXT,
  description_md TEXT, status TEXT, priority INTEGER, owner TEXT,
  blocked_reason TEXT, order_index INTEGER, due_date TEXT,
  created_at TEXT, updated_at TEXT, started_at TEXT, resolved_at TEXT
);
CREATE TABLE workflow_state (
  id INTEGER PRIMARY KEY, active_cycle_slug TEXT, phase TEXT, actor TEXT,
  started_at TEXT, lock_token TEXT, updated_at TEXT
);
CREATE TABLE task_claims (
  id INTEGER PRIMARY KEY, task_id INTEGER, actor TEXT, attempt INTEGER,
  input_hash TEXT, lease_until INTEGER, status TEXT, claimed_at TEXT, released_at TEXT
);
CREATE TABLE task_dependencies (
  id INTEGER PRIMARY KEY, task_id INTEGER, depends_on_task_id INTEGER,
  type TEXT, created_at TEXT
);
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY, ts TEXT, agent TEXT, action TEXT,
  table_name TEXT, row_id INTEGER, details TEXT, actor_source TEXT
);
CREATE TABLE receipts (
  id TEXT PRIMARY KEY, task_id TEXT, agent TEXT, command TEXT,
  exit_code INTEGER, output_summary TEXT, ts TEXT, tree_hash TEXT
);
CREATE TABLE attempts (
  id INTEGER PRIMARY KEY, token TEXT, change_name TEXT, request_id TEXT,
  work_unit TEXT, attempts_used INTEGER, max_attempts INTEGER, state TEXT,
  outcome TEXT, evidence TEXT, created_at TEXT, updated_at TEXT
);
CREATE TABLE routing_decisions (
  id INTEGER PRIMARY KEY, ts TEXT, user_intent TEXT, chosen_route TEXT,
  route_reason TEXT, agents_involved TEXT, outcome TEXT, completed_at TEXT
);
CREATE TABLE workflow_metrics (
  request_id TEXT PRIMARY KEY, risk_level TEXT, route TEXT,
  agents_count INTEGER, handoffs INTEGER, permission_prompts INTEGER,
  context_bytes INTEGER, started_at TEXT, completed_at TEXT,
  duration_ms INTEGER, outcome TEXT
);
CREATE TABLE concepts (id INTEGER PRIMARY KEY, slug TEXT, title TEXT, body_md TEXT, category TEXT, updated_at TEXT);
CREATE TABLE decisions (id INTEGER PRIMARY KEY, slug TEXT, title TEXT, body_md TEXT, status TEXT, decided_at TEXT, decided_by TEXT);
CREATE TABLE preferences (id INTEGER PRIMARY KEY, slug TEXT, scope TEXT, scope_value TEXT, body_md TEXT, confidence REAL, source TEXT);
CREATE TABLE known_problems (id INTEGER PRIMARY KEY, slug TEXT, title TEXT, symptom_md TEXT, workaround_md TEXT, status TEXT, discovered_at TEXT, resolved_at TEXT);
"""


class DashboardDataTest(unittest.TestCase):
    def setUp(self):
        handle, self.db_path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        self.addCleanup(lambda: os.path.exists(self.db_path) and os.unlink(self.db_path))
        conn = sqlite3.connect(self.db_path)
        conn.executescript(SCHEMA)
        conn.execute("INSERT INTO schema_meta VALUES ('version', 'test')")
        conn.execute("INSERT INTO plans VALUES (1,'release','Release','in_progress','sol','2026-01-01','2026-01-02',NULL)")
        conn.executemany(
            "INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [
                (1,1,'done','Terminada','', 'resolved',1,'teo',None,1,None,'2026-01-01','2026-01-02','2026-01-01','2026-01-02'),
                (2,1,'active','Implementar','', 'in_progress',1,'jhon',None,2,None,'2026-01-01','2026-01-03','2026-01-03',None),
                (3,1,'blocked','Publicar','', 'blocked',2,'pau','Falta revisión',3,None,'2026-01-01','2026-01-03',None,None),
                (4,1,'next','Documentar','', 'pending',3,'luz',None,4,None,'2026-01-01','2026-01-03',None,None),
            ],
        )
        conn.execute("INSERT INTO task_dependencies VALUES (1,3,2,'blocks','2026-01-03')")
        conn.execute("INSERT INTO task_claims VALUES (1,2,'jhon',1,'hash',9999999999,'active','2026-01-03',NULL)")
        conn.execute("INSERT INTO workflow_state VALUES (1,'release','build','jhon','2026-01-03','lock','2026-01-03')")
        conn.execute("INSERT INTO audit_log VALUES (1,'2026-01-03','jhon','update','tasks',2,'{\"status\":\"in_progress\"}','helper')")
        conn.execute("INSERT INTO receipts VALUES ('r1','2','jhon','pytest',0,'ok','2026-01-03','abc')")
        conn.commit()
        conn.close()

    def test_overview_uses_canonical_terminal_states_and_reports_next_work(self):
        data = dashboard.DashboardData(self.db_path).overview()
        self.assertEqual(data["progress"], {"done": 1, "total": 4, "percent": 25})
        self.assertEqual(data["workflow"]["phase"], "build")
        self.assertEqual(data["blockers"][0]["blocked_reason"], "Falta revisión")
        self.assertEqual(data["next_tasks"][0]["slug"], "next")

    def test_agents_combines_owners_with_active_claims(self):
        agents = dashboard.DashboardData(self.db_path).agents()
        jhon = next(agent for agent in agents if agent["name"] == "jhon")
        self.assertEqual(jhon["state"], "working")
        self.assertEqual(jhon["current_task"]["slug"], "active")
        self.assertEqual(jhon["role"], "Verificación")
        luz = next(agent for agent in agents if agent["name"] == "luz")
        self.assertEqual(luz["state"], "waiting")

    def test_agents_includes_the_complete_team_even_when_idle(self):
        agents = dashboard.DashboardData(self.db_path).agents()
        self.assertEqual(
            {agent["name"].lower() for agent in agents},
            {"alex", "jes", "jhon", "luz", "pau", "pol", "sol", "teo"},
        )

    def test_timeline_normalizes_audit_and_receipts(self):
        events = dashboard.DashboardData(self.db_path).timeline(limit=10)
        self.assertEqual({event["kind"] for event in events}, {"activity", "verification"})
        self.assertTrue(all("summary" in event for event in events))

    def test_change_token_changes_when_database_changes(self):
        data = dashboard.DashboardData(self.db_path)
        before = data.change_token()
        conn = sqlite3.connect(self.db_path)
        conn.execute("UPDATE tasks SET status='approved' WHERE id=2")
        conn.commit()
        conn.close()
        after = data.change_token()
        self.assertNotEqual(before, after)

    def test_read_errors_are_not_disguised_as_rows(self):
        with self.assertRaises(dashboard.DashboardError):
            dashboard.DashboardData(self.db_path).query("SELECT * FROM missing_table")

    def test_preferences_can_be_searched_without_a_title_column(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute("INSERT INTO preferences VALUES (1,'tono','global',NULL,'Comunicar claro',.9,'user')")
        conn.commit()
        conn.close()
        self.assertEqual(dashboard.DashboardData(self.db_path).memory("preferences", "tono")[0]["slug"], "tono")


class DashboardHtmlContractTest(unittest.TestCase):
    def test_dashboard_is_accessible_responsive_and_has_required_views(self):
        html = (ROOT / "web" / "teamdb-dashboard.html").read_text(encoding="utf-8")
        for marker in (
            'data-view="overview"',
            'data-view="flow"',
            'data-view="history"',
            'data-view="memory"',
            'id="last-updated"',
            'aria-live="polite"',
            'prefers-reduced-motion',
            '100dvh',
        ):
            self.assertIn(marker, html)
        self.assertNotIn("cdn.jsdelivr.net", html)
        self.assertNotIn("unpkg.com", html)


if __name__ == "__main__":
    unittest.main()
