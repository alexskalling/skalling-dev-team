#!/usr/bin/env python3
"""Servidor local y de solo lectura para el centro de control TeamDB."""

import hashlib
import http.server
import json
import os
import sqlite3
import urllib.parse
from pathlib import Path

PORT = int(os.environ.get("TDB_PORT", "3741"))
DB_PATH = os.environ.get("TDB_DB", "")
HTML_PATH = os.environ.get("TDB_HTML", "")
PROJECT_NAME = os.environ.get("TDB_PROJECT", "proyecto")
TERMINAL_TASK_STATES = ("approved", "resolved")
TEAM_ROSTER = ("alex", "jes", "jhon", "luz", "pau", "pol", "sol", "teo")
TEAM_ROLES = {
    "alex": "Orquestación",
    "jes": "Investigación",
    "jhon": "Verificación",
    "luz": "Calidad y seguridad",
    "pau": "Memoria",
    "pol": "Producto",
    "sol": "Planificación",
    "teo": "Ingeniería",
}


class DashboardError(RuntimeError):
    """Error legible para el cliente."""


class DashboardData:
    def __init__(self, db_path):
        self.db_path = str(db_path)

    def _connect(self):
        if not os.path.isfile(self.db_path):
            raise DashboardError("No se encontró team.db. Ejecuta /skalling-init.")
        try:
            uri = Path(self.db_path).resolve().as_uri() + "?mode=ro"
            conn = sqlite3.connect(uri, uri=True, timeout=2)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA query_only=ON")
            return conn
        except sqlite3.Error as exc:
            raise DashboardError(f"No se pudo abrir TeamDB: {exc}") from exc

    def query(self, sql, params=()):
        try:
            with self._connect() as conn:
                return [dict(row) for row in conn.execute(sql, params).fetchall()]
        except DashboardError:
            raise
        except sqlite3.Error as exc:
            raise DashboardError(f"TeamDB no pudo responder la consulta: {exc}") from exc

    def one(self, sql, params=(), default=None):
        rows = self.query(sql, params)
        return rows[0] if rows else default

    def table_exists(self, table):
        return bool(self.one("SELECT 1 AS present FROM sqlite_master WHERE type='table' AND name=?", (table,)))

    @staticmethod
    def _status_counts(tasks):
        counts = {}
        for task in tasks:
            status = task.get("status") or "unknown"
            counts[status] = counts.get(status, 0) + 1
        return counts

    def overview(self):
        workflow = self.one("SELECT * FROM workflow_state WHERE id=1", default={}) if self.table_exists("workflow_state") else {}
        plan = None
        if workflow.get("active_cycle_slug"):
            plan = self.one("SELECT * FROM plans WHERE slug=?", (workflow["active_cycle_slug"],))
        if not plan:
            plan = self.one(
                "SELECT * FROM plans WHERE status IN ('in_progress','approved') "
                "ORDER BY CASE status WHEN 'in_progress' THEN 0 ELSE 1 END, updated_at DESC LIMIT 1"
            )
        tasks = self.query(
            "SELECT * FROM tasks" + (" WHERE plan_id=?" if plan else "") + " ORDER BY priority, order_index, id",
            (plan["id"],) if plan else (),
        )
        done = sum(task.get("status") in TERMINAL_TASK_STATES for task in tasks)
        dependencies = self.dependencies()
        blocked_by_dependency = {
            edge["task_id"] for edge in dependencies
            if edge.get("type") == "blocks" and edge.get("dependency_status") not in TERMINAL_TASK_STATES
        }
        total = len(tasks)
        return {
            "workflow": workflow,
            "plan": plan,
            "progress": {"done": done, "total": total, "percent": round(done * 100 / total) if total else 0},
            "active_tasks": [task for task in tasks if task.get("status") in ("in_progress", "in_review")],
            "blockers": [task for task in tasks if task.get("status") == "blocked"],
            "next_tasks": [task for task in tasks if task.get("status") == "pending" and task.get("id") not in blocked_by_dependency][:5],
            "status_counts": self._status_counts(tasks),
        }

    def plans(self):
        return self.query(
            "SELECT p.*, COUNT(t.id) AS tasks_total, "
            "SUM(CASE WHEN t.status IN ('approved','resolved') THEN 1 ELSE 0 END) AS tasks_done "
            "FROM plans p LEFT JOIN tasks t ON t.plan_id=p.id GROUP BY p.id "
            "ORDER BY CASE p.status WHEN 'in_progress' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END, p.updated_at DESC"
        )

    def tasks(self):
        claim_join = "LEFT JOIN task_claims c ON c.task_id=t.id AND c.status='active'" if self.table_exists("task_claims") else "LEFT JOIN (SELECT NULL task_id, NULL actor, NULL lease_until) c ON 0"
        return self.query(
            "SELECT t.*, p.slug AS plan_slug, p.title AS plan_title, c.actor AS claimed_by, c.lease_until "
            f"FROM tasks t LEFT JOIN plans p ON p.id=t.plan_id {claim_join} "
            "ORDER BY t.priority, t.order_index, t.id"
        )

    def dependencies(self):
        if not self.table_exists("task_dependencies"):
            return []
        return self.query(
            "SELECT d.*, t.slug AS task_slug, t.title AS task_title, dep.slug AS dependency_slug, "
            "dep.title AS dependency_title, dep.status AS dependency_status FROM task_dependencies d "
            "JOIN tasks t ON t.id=d.task_id JOIN tasks dep ON dep.id=d.depends_on_task_id ORDER BY d.id"
        )

    def agents(self):
        tasks = self.tasks()
        names = set(TEAM_ROSTER)
        names.update(task.get("owner", "").lower() for task in tasks if task.get("owner") and task.get("owner").lower() != "system")
        names.update(task.get("claimed_by", "").lower() for task in tasks if task.get("claimed_by") and task.get("claimed_by").lower() != "system")
        workflow = self.one("SELECT actor FROM workflow_state WHERE id=1", default={}) if self.table_exists("workflow_state") else {}
        if workflow.get("actor") and workflow["actor"].lower() != "system":
            names.add(workflow["actor"].lower())
        result = []
        for name in sorted(names):
            assigned = [task for task in tasks if (task.get("owner") or "").lower() == name]
            current = next((task for task in tasks if (task.get("claimed_by") or "").lower() == name), None)
            current = current or next((task for task in assigned if task.get("status") in ("in_progress", "in_review")), None)
            result.append({
                "name": name,
                "role": TEAM_ROLES.get(name, "Colaborador"),
                "state": "working" if current else "waiting",
                "current_task": current,
                "assigned": len(assigned),
                "completed": sum(task.get("status") in TERMINAL_TASK_STATES for task in assigned),
                "blocked": sum(task.get("status") == "blocked" for task in assigned),
            })
        return result

    def timeline(self, limit=100):
        limit = max(1, min(int(limit), 500))
        events = []
        if self.table_exists("audit_log"):
            for row in self.query("SELECT * FROM audit_log ORDER BY ts DESC LIMIT ?", (limit,)):
                events.append({"kind": "activity", "ts": row.get("ts"), "agent": row.get("agent") or "sistema", "summary": f"{row.get('action') or 'cambio'} en {row.get('table_name') or 'TeamDB'}", "detail": row.get("details") or ""})
        if self.table_exists("receipts"):
            for row in self.query("SELECT * FROM receipts ORDER BY ts DESC LIMIT ?", (limit,)):
                outcome = "pasó" if row.get("exit_code") == 0 else "falló"
                events.append({"kind": "verification", "ts": row.get("ts"), "agent": row.get("agent") or "sistema", "summary": f"Verificación {outcome}: {row.get('command') or 'comando'}", "detail": row.get("output_summary") or ""})
        if self.table_exists("attempts"):
            for row in self.query("SELECT * FROM attempts ORDER BY updated_at DESC LIMIT ?", (limit,)):
                events.append({"kind": "attempt", "ts": row.get("updated_at"), "agent": "equipo", "summary": f"Intento {row.get('attempts_used', 0)}/{row.get('max_attempts', 0)}: {row.get('change_name')}", "detail": row.get("evidence") or row.get("outcome") or row.get("state") or ""})
        return sorted(events, key=lambda event: event.get("ts") or "", reverse=True)[:limit]

    def memory(self, kind, search="", limit=100):
        definitions = {
            "concepts": ("concepts", "updated_at", "title"),
            "decisions": ("decisions", "decided_at", "title"),
            "preferences": ("preferences", "slug", "body_md"),
            "problems": ("known_problems", "discovered_at", "title"),
        }
        if kind not in definitions:
            raise DashboardError("Tipo de memoria no válido.")
        table, order, search_column = definitions[kind]
        limit = max(1, min(int(limit), 250))
        if search:
            pattern = f"%{search}%"
            return self.query(f"SELECT * FROM {table} WHERE slug LIKE ? OR COALESCE({search_column},'') LIKE ? ORDER BY {order} DESC LIMIT ?", (pattern, pattern, limit))
        return self.query(f"SELECT * FROM {table} ORDER BY {order} DESC LIMIT ?", (limit,))

    def system(self):
        version = self.one("SELECT value FROM schema_meta WHERE key='version'", default={})
        counts = {}
        for table in ("plans", "tasks", "concepts", "decisions", "known_problems", "audit_log", "receipts"):
            if self.table_exists(table):
                counts[table] = self.one(f"SELECT COUNT(*) AS count FROM {table}")["count"]
        return {"database": self.db_path, "size_bytes": os.path.getsize(self.db_path), "schema_version": version.get("value", "?"), "counts": counts, "read_only": True}

    def change_token(self):
        parts = []
        for path in (self.db_path, self.db_path + "-wal"):
            try:
                stat = os.stat(path)
                parts.extend((path, str(stat.st_mtime_ns), str(stat.st_size)))
            except FileNotFoundError:
                continue
        return hashlib.sha256("|".join(parts).encode()).hexdigest()[:16]


class Handler(http.server.BaseHTTPRequestHandler):
    data = DashboardData(DB_PATH)

    def _headers(self, status, content_type, length):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:")
        self.end_headers()

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, default=str).encode("utf-8")
        self._headers(status, "application/json; charset=utf-8", len(body))
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)
        try:
            routes = {
                "/api/health": lambda: {"ok": True, "project": PROJECT_NAME},
                "/api/info": lambda: {"project": PROJECT_NAME, **self.data.system()},
                "/api/overview": self.data.overview,
                "/api/plans": self.data.plans,
                "/api/tasks": self.data.tasks,
                "/api/dependencies": self.data.dependencies,
                "/api/agents": self.data.agents,
                "/api/timeline": lambda: self.data.timeline(params.get("limit", [100])[0]),
                "/api/system": self.data.system,
                "/api/changes": lambda: {"token": self.data.change_token()},
                "/api/memory": lambda: self.data.memory(params.get("kind", ["concepts"])[0], params.get("q", [""])[0], params.get("limit", [100])[0]),
            }
            if path in routes:
                self.send_json(routes[path]())
            elif path in ("/", "/index.html"):
                body = Path(HTML_PATH).read_bytes()
                self._headers(200, "text/html; charset=utf-8", len(body))
                self.wfile.write(body)
            else:
                self.send_json({"error": "Ruta no encontrada."}, 404)
        except (DashboardError, OSError, ValueError) as exc:
            self.send_json({"error": str(exc), "action": "Revisa /skalling-doctor y vuelve a intentar."}, 500)

    def do_POST(self):
        self.send_json({"error": "El Dashboard es de solo lectura."}, 405)

    def log_message(self, *_args):
        pass


class DashboardServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"PORT={PORT}", flush=True)
    with DashboardServer(("127.0.0.1", PORT), Handler) as server:
        server.serve_forever()
