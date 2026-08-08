#!/usr/bin/env python3
"""HTTP server for TeamDB dashboard — queries SQLite directly, returns JSON."""
import http.server
import socketserver
import os
import json
import urllib.parse
import sqlite3
import time
import re

PORT = int(os.environ.get("TDB_PORT", "3741"))
DB_PATH = os.environ.get("TDB_DB", "")
HTML_PATH = os.environ.get("TDB_HTML", "")
PROJECT_NAME = os.environ.get("TDB_PROJECT", "proyecto")
TIMEOUT_FILE = os.environ.get("TDB_TIMEOUT_FILE", "")


def query_db(sql, params=()):
    if not os.path.exists(DB_PATH):
        return []
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute(sql, params)
        rows = cur.fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        return [{"_error": str(e)}]


def val(sql):
    rows = query_db(sql)
    return rows[0][list(rows[0].keys())[0]] if rows else None


class Handler(http.server.BaseHTTPRequestHandler):
    def send_json(self, data):
        body = json.dumps(data, default=str).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def touch_timeout(self):
        if TIMEOUT_FILE:
            with open(TIMEOUT_FILE, "w") as f:
                f.write(str(int(time.time())))

    def do_GET(self):
        self.touch_timeout()

        if self.path == "/api/heartbeat":
            self.send_json({"ok": True})
            return

        if self.path == "/api/info":
            self.send_json({
                "project": PROJECT_NAME,
                "db": DB_PATH,
                "exists": os.path.exists(DB_PATH),
                "size": os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0,
            })
            return

        if self.path == "/api/stats":
            c = val("SELECT COUNT(*) FROM concepts") or 0
            d = val("SELECT COUNT(*) FROM decisions") or 0
            p = val("SELECT COUNT(*) FROM plans") or 0
            tasks = query_db("SELECT status FROM tasks")
            done = sum(1 for t in tasks if t.get("status") == "done")
            total = len(tasks)
            pct = round(done / total * 100) if total else 0
            pb = val("SELECT COUNT(*) FROM known_problems") or 0
            lnk = val("SELECT COUNT(*) FROM memory_links") or 0
            ver = val("SELECT value FROM schema_meta WHERE key='version'") or "?"
            self.send_json({
                "concepts": c, "decisions": d, "plans": p,
                "tasks_done": done, "tasks_total": total, "tasks_pct": pct,
                "problems": pb, "links": lnk, "version": ver,
            })
            return

        if self.path == "/api/plans":
            plans = query_db("""
                SELECT p.*, COUNT(t.id) as tt,
                       SUM(CASE WHEN t.status='done' THEN 1 ELSE 0 END) as td
                FROM plans p LEFT JOIN tasks t ON t.plan_id=p.id GROUP BY p.id ORDER BY p.created_at DESC
            """)
            self.send_json(plans)
            return

        if self.path == "/api/plans-hierarchy":
            wip = query_db("SELECT * FROM work_in_progress ORDER BY type, slug")
            plans_wip = [w for w in wip if w.get("type") == "plan"]
            features_wip = [w for w in wip if w.get("type") == "feature"]
            tasks_wip = [w for w in wip if w.get("type") == "task"]

            by_parent = {}
            for f in features_wip:
                pid = f.get("parent_id")
                if pid not in by_parent:
                    by_parent[pid] = []
                by_parent[pid].append({**f, "_children": []})

            for t in tasks_wip:
                pid = t.get("parent_id")
                if pid not in by_parent:
                    by_parent[pid] = []
                by_parent[pid].append({**t, "_children": []})

            for f in features_wip:
                f["_children"] = by_parent.get(f["id"], [])

            by_plan = {}
            for f in features_wip:
                pid = f.get("parent_id")
                if pid not in by_plan:
                    by_plan[pid] = []
                by_plan[pid].append(f)

            result = []
            for p in plans_wip:
                pid = p["id"]
                result.append({
                    **p,
                    "_type": "wip",
                    "_features": by_plan.get(pid, []),
                    "_flat_tasks": [],
                })

            self.send_json(result)
            return

        if self.path == "/api/tasks":
            tasks = query_db("""
                SELECT t.*, p.slug as ps, p.title as pt
                FROM tasks t LEFT JOIN plans p ON p.id=t.plan_id ORDER BY t.order_index ASC
            """)
            self.send_json(tasks)
            return

        if self.path == "/api/concepts":
            self.send_json(query_db("SELECT * FROM concepts ORDER BY category, slug"))
            return

        if self.path == "/api/decisions":
            self.send_json(query_db("SELECT * FROM decisions ORDER BY decided_at DESC"))
            return

        if self.path == "/api/problems":
            self.send_json(query_db("SELECT * FROM known_problems ORDER BY discovered_at DESC"))
            return

        if self.path == "/api/preferences":
            self.send_json(query_db("SELECT * FROM preferences ORDER BY scope, slug"))
            return

        if self.path == "/api/graph":
            nodes = {}
            for c in query_db("SELECT id, slug, category FROM concepts"):
                nodes["c" + str(c["id"])] = {"slug": c["slug"], "type": "concept", "category": c.get("category", "")}
            for d in query_db("SELECT id, slug, status FROM decisions"):
                nodes["d" + str(d["id"])] = {"slug": d["slug"], "type": "decision", "status": d.get("status", "")}
            for p in query_db("SELECT id, slug, status FROM plans"):
                nodes["p" + str(p["id"])] = {"slug": p["slug"], "type": "plan", "status": p.get("status", "")}
            for t in query_db("SELECT id, slug, status, plan_id FROM tasks"):
                nodes["t" + str(t["id"])] = {"slug": t["slug"], "type": "task", "status": t.get("status", ""), "plan_id": t.get("plan_id", "")}
            for w in query_db("SELECT id, slug, type, status FROM work_in_progress WHERE type IN ('feature','task')"):
                nodes["w" + w["slug"]] = {"slug": w["slug"], "type": w["type"], "category": "wip", "status": w.get("status", "")}

            links = query_db("""
                SELECT ml.*,
                       COALESCE(c1.slug,d1.slug,w1.slug,p1.slug,t1.slug) as fs, COALESCE(c2.slug,d2.slug,w2.slug,p2.slug,t2.slug) as ts
                FROM memory_links ml
                LEFT JOIN concepts c1 ON ml.from_table='concepts' AND c1.id=ml.from_id
                LEFT JOIN decisions d1 ON ml.from_table='decisions' AND d1.id=ml.from_id
                LEFT JOIN work_in_progress w1 ON ml.from_table='work_in_progress' AND w1.id=ml.from_id
                LEFT JOIN plans p1 ON ml.from_table='plans' AND p1.id=ml.from_id
                LEFT JOIN tasks t1 ON ml.from_table='tasks' AND t1.id=ml.from_id
                LEFT JOIN concepts c2 ON ml.to_table='concepts' AND c2.id=ml.to_id
                LEFT JOIN decisions d2 ON ml.to_table='decisions' AND d2.id=ml.to_id
                LEFT JOIN work_in_progress w2 ON ml.to_table='work_in_progress' AND w2.id=ml.to_id
                LEFT JOIN plans p2 ON ml.to_table='plans' AND p2.id=ml.to_id
                LEFT JOIN tasks t2 ON ml.to_table='tasks' AND t2.id=ml.to_id
            """)
            links = [l for l in links if l.get("fs") and l.get("ts")]
            self.send_json({"nodes": nodes, "links": links})
            return

        if self.path == "/api/codegraph":
            cached_nodes = query_db("SELECT node_path as path, node_lang as lang, node_type as type FROM code_graph_cache")
            cached_edges = query_db("SELECT from_path as 'from', to_path as 'to' FROM code_imports")
            if not cached_nodes:
                self.send_json({"nodes": [], "edges": [], "cached": False})
            else:
                self.send_json({"nodes": cached_nodes, "edges": cached_edges, "cached": True})
            return

        if self.path in ("/", "/index.html"):
            serve_path = HTML_PATH
        else:
            serve_path = urllib.parse.unquote(self.path[1:])

        if serve_path and os.path.exists(serve_path):
            ct = "text/html" if serve_path.endswith(".html") else "application/octet-stream"
            with open(serve_path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ct)
            self.send_header("Content-Length", len(data))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def _refresh_codegraph(self):
        """Refresca el code graph: escanea archivos del proyecto, parsea imports."""
        import time
        PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(DB_PATH)))

        EXCLUDE_DIRS = {
            "node_modules", ".git", ".next", ".nuxt", ".svelte-kit",
            "dist", "build", "target", "out", "__pycache__", ".pytest_cache",
            ".venv", "venv", ".env", ".tox", "vendor", "bin", "obj",
        }
        LANG_EXTS = {
            ".ts": "typescript", ".tsx": "typescript", ".js": "javascript", ".jsx": "javascript",
            ".py": "python", ".rs": "rust", ".go": "go", ".java": "java",
        }
        IMPORT_PATTERNS = {
            "typescript": [r'''from\s+['"]([^'"]+)['"]''', r'''import\s+.*?\s+from\s+['"]([^'"]+)['"]'''],
            "javascript": [r'''from\s+['"]([^'"]+)['"]''', r'''import\s+.*?\s+from\s+['"]([^'"]+)['"]'''],
            "python": [r'''^import\s+(\S+)''', r'''^from\s+(\S+)\s+import'''],
        }

        exts = set(LANG_EXTS.keys())
        nodes = {}
        edges = []
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ")

        for root, dirs, files in os.walk(PROJECT_ROOT):
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not d.startswith(".")]
            for f in files:
                if not any(f.endswith(e) for e in exts):
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, PROJECT_ROOT).replace("\\", "/")
                lang = LANG_EXTS.get(os.path.splitext(f)[1], "unknown")
                nodes[rel] = {"path": rel, "type": "source", "lang": lang}

        for rel in nodes:
            full = os.path.join(PROJECT_ROOT, rel)
            lang = nodes[rel].get("lang", "unknown")
            if lang not in IMPORT_PATTERNS:
                continue
            try:
                txt = open(full, "r", encoding="utf-8", errors="ignore").read()
                for pattern in IMPORT_PATTERNS[lang]:
                    for m in re.finditer(pattern, txt, re.MULTILINE):
                        imp = m.group(1)
                        if lang in ("typescript", "javascript"):
                            if imp.startswith("."):
                                resolved = os.path.normpath(os.path.join(os.path.dirname(rel), imp)).replace("\\", "/")
                                if not any(resolved.endswith(e) for e in exts):
                                    for ext in [".ts", ".tsx", ".js", ".jsx"]:
                                        if resolved + ext in nodes:
                                            resolved += ext
                                            break
                                    else:
                                        resolved += ".ts"
                                if resolved in nodes and resolved != rel:
                                    edges.append((rel, resolved))
                            elif imp.startswith("@/"):
                                resolved = imp[2:]
                                if not any(resolved.endswith(e) for e in exts):
                                    for ext in [".ts", ".tsx", ".js", ".jsx"]:
                                        if resolved + ext in nodes:
                                            resolved += ext
                                            break
                                        else:
                                            resolved += ".ts"
                                if resolved in nodes:
                                    edges.append((rel, resolved))
                        elif lang == "python" and "." in imp:
                            imp_path = imp.replace(".", "/")
                            if imp_path + ".py" in nodes:
                                edges.append((rel, imp_path + ".py"))
            except Exception:
                pass

        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM code_imports")
        conn.execute("DELETE FROM code_graph_cache")
        for path, n in nodes.items():
            conn.execute(
                "INSERT OR REPLACE INTO code_graph_cache (node_path, node_lang, node_type, updated_at) VALUES (?, ?, ?, ?)",
                (path, n["lang"], n["type"], now)
            )
        for frm, to in edges:
            conn.execute(
                "INSERT OR IGNORE INTO code_imports (from_path, to_path, updated_at) VALUES (?, ?, ?)",
                (frm, to, now)
            )
        conn.commit()
        conn.close()

        self.send_json({"nodes": len(nodes), "edges": len(edges), "updated_at": now})

    def do_POST(self):
        self.touch_timeout()
        if self.path == "/api/codegraph/refresh":
            self._refresh_codegraph()
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"PORT={PORT}", flush=True)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        httpd.serve_forever()
