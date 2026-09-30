"""Bounded source inventory and explicit freshness for retrieved project memory."""
import hashlib
import json
import re
import os
from pathlib import Path

IGNORED = {'node_modules', 'dist', 'build', 'coverage', 'vendor', '__pycache__', 'venv'}
SOURCES = ('README.md', 'package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml',
           'Gemfile', 'composer.json', 'VERSION', '.opencode/project.yaml')


def modules(project):
    return sorted(p.name for p in Path(project).iterdir()
                  if p.is_dir() and not p.is_symlink() and not p.name.startswith('.')
                  and p.name not in IGNORED)


def source_fingerprint(project):
    project = Path(project)
    digest = hashlib.sha256(json.dumps(modules(project)).encode())
    for name in SOURCES:
        path = project / name
        digest.update(name.encode())
        if path.is_file() and not path.is_symlink():
            digest.update(path.read_bytes())
    # Cheap source-change detector, not a verification/receipt hash. Include
    # nested sources without reading their contents on every context request.
    # Ignore mutable agent memory and generated dependencies to avoid self-drift.
    for directory, dirs, names in os.walk(project):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.') and d not in IGNORED
                         and not (Path(directory) / d).is_symlink())
        for name in sorted(names):
            path = Path(directory) / name
            relative = path.relative_to(project).as_posix()
            if path.is_symlink() or relative.startswith('db/teamdb/') or path.suffix not in {
                '.ts', '.tsx', '.js', '.jsx', '.mjs', '.py', '.sh', '.sql', '.css',
                '.scss', '.sass', '.less', '.go', '.rs', '.java', '.rb', '.php', '.vue', '.svelte'
            }:
                continue
            st = path.stat()
            digest.update(f'{relative}:{st.st_size}:{st.st_mtime_ns}:{st.st_ctime_ns}'.encode())
    return digest.hexdigest()


def freshness(conn, project):
    rows = dict(conn.execute("SELECT key,value FROM schema_meta WHERE key='bootstrap.sources' "
                             "OR key LIKE 'bootstrap.pending.%'"))
    recorded = rows.get('bootstrap.sources')
    pending = sorted(k.removeprefix('bootstrap.pending.') for k in rows if k.startswith('bootstrap.pending.'))
    try:
        current = source_fingerprint(project) if recorded else None
    except OSError:
        current = None  # A concurrent source edit must not hide all memory.
    return {'status': ('unknown' if not recorded else
                       'current' if recorded == current else 'stale'),
            'pending_review': pending}


def memory_item(table, item, body_key, seen=()):
    """A caller may omit a body only when it already holds this exact revision."""
    identity = hashlib.sha256(json.dumps({'slug': item['slug'], 'title': item.get('title', ''),
        'body': item.get(body_key, '')}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    token = f"{table}:{item['slug']}:{identity}"
    item['read_key'] = token
    if token in seen:
        item.pop(body_key, None)
        item['already_read'] = True
    return item


def request_context(conn, project, query, top_k=8, max_bytes=8000, visual=False, options=()):
    """Bounded retrieval, shared by CLI and workflow delivery."""
    if not 1 <= top_k <= 50 or not 512 <= max_bytes <= 100000:
        raise ValueError("top-k must be 1..50 and max-bytes 512..100000")
    terms = list(dict.fromkeys(re.findall(r"[a-z0-9áéíóúñü]{3,}", query.lower())))
    stop = {"para", "con", "que", "los", "las", "del", "una", "por", "the", "and"}
    stop.update({"quiero", "necesito", "hacer", "esto", "este", "esta", "como", "pero", "porque", "más", "sin", "del", "los", "las"})
    terms = [term for term in terms if term not in stop][:24]
    anchors = list(dict.fromkeys(x.lower() for x in options if x and not x.startswith("seen:")))[:16]
    visual = visual or any(t in terms for t in
        ("estilos", "estilo", "diseño", "css", "tipografía", "paleta", "layout"))
    tables = {
        "concepts": ("title", "body_md", ""),
        "decisions": ("title", "body_md", "status='accepted'"),
        "known_problems": ("title", "coalesce(symptom_md,'') || char(10) || coalesce(workaround_md,'')", "status='open'"),
        "preferences": ("slug", "body_md", ""),
    }
    result = {key: [] for key in tables}
    result.update(omitted=[], needs_expansion=False, more_matches=False, freshness=freshness(conn, project))
    seen = {x[5:] for x in options if x.startswith("seen:")}
    def encode():
        return json.dumps(result, ensure_ascii=False, separators=(",", ":"))
    candidates = []
    for table, (title, body, guard) in tables.items():
        clauses, params = [], []
        for term in terms:
            clauses.append("(lower(slug) LIKE ? OR lower(" + title + ") LIKE ? OR lower(coalesce(" + body + ",'')) LIKE ?)")
            params.extend(["%" + term + "%"] * 3)
        for anchor in anchors:
            clauses.append("instr(lower(coalesce(" + body + ",'')), ?) > 0")
            params.append(anchor)
        if table == "concepts":
            clauses.append("slug IN ('project-summary','project-stack'" + (",'design-system'" if visual else "") + ")")
        if not clauses:
            continue
        where = "(" + " OR ".join(clauses) + ")" + (" AND " + guard if guard else "")
        # Rank matches in SQL before limiting; short titles alone never replace a rule's full body.
        score_parts, score_params = [], []
        for term in terms:
            score_parts.append("(CASE WHEN lower(" + title + ") LIKE ? THEN 4 ELSE 0 END + CASE WHEN lower(coalesce(" + body + ",'')) LIKE ? THEN 1 ELSE 0 END)")
            score_params.extend(["%" + term + "%"] * 2)
        for anchor in anchors:
            score_parts.append("CASE WHEN instr(lower(coalesce(" + body + ",'')), ?) > 0 THEN 100 ELSE 0 END")
            score_params.append(anchor)
        score = " + ".join(score_parts) or "0"
        priority = ("CASE slug WHEN 'project-summary' THEN 10000 WHEN 'design-system' THEN "
                    + ("9000" if visual else "0") + " WHEN 'project-stack' THEN 8000 ELSE 0 END") if table == "concepts" else "0"
        rows = conn.execute("SELECT slug," + title + ",coalesce(" + body + ",''),(" + priority +
                            " + " + score + ") AS rank FROM " + table + " WHERE " + where +
                            " ORDER BY rank DESC,slug LIMIT ?", score_params + params + [top_k + 1]).fetchall()
        if len(rows) > top_k:
            # Hay más coincidencias que top_k: nunca se esconde. Quien recibe la
            # cápsula amplía por needs_expansion/omitted (auditoría v0.12.0 #6).
            result["more_matches"] = True
            result["needs_expansion"] = True
            result["omitted"].append({"table": table, "slug": rows[top_k][0]})
        for slug, heading, body_text, rank in rows[:top_k]:
            candidates.append((rank, table, {"slug": slug, "title": heading, "body": body_text}))
    for _, table, item in sorted(candidates, key=lambda row: (-row[0], row[1], row[2]["slug"])):
        item = memory_item(table, item, "body", seen)
        result[table].append(item)
        # Reserve space to identify omitted rows; never silently slice a decision.
        if len(encode().encode()) > max_bytes - 192:
            result[table].pop()
            result["needs_expansion"] = True
            ref = {"table": table, "slug": item["slug"]}
            result["omitted"].append(ref)
            if len(encode().encode()) > max_bytes:
                result["omitted"].pop()
                result["more_matches"] = True
    return result


def task_context(conn, project, plan_slug, task_slug, top_k=8, max_bytes=8000, discover=True, seen=()):
    """Linked constraints first, automatic relevant memories second; no N+1 reads."""
    if not 1 <= top_k <= 50 or not 512 <= max_bytes <= 100000:
        raise ValueError('top-k must be 1..50 and max-bytes 512..100000')
    tables = ('concepts', 'decisions', 'preferences', 'known_problems')
    output = {k: [] for k in tables}
    output.update(task=None, plan=None)
    plan = conn.execute('SELECT id,slug,title FROM plans WHERE slug=?', (plan_slug,)).fetchone()
    if not plan:
        return output
    output['plan'] = dict(zip(('slug', 'title'), plan[1:]))
    row = conn.execute('SELECT id,slug,title,status,description_md,acceptance_md,purpose FROM tasks '
                       'WHERE plan_id=? AND slug=?', (plan[0], task_slug)).fetchone()
    if not row:
        return output
    output['task'] = dict(zip(('slug', 'title', 'status', 'description_md', 'acceptance_md', 'purpose'), row[1:]))
    output.update(omitted=[], needs_expansion=False, more_matches=False, freshness=freshness(conn, project))
    selected = {k: set() for k in tables}
    def size():
        return len(json.dumps(output, ensure_ascii=False, separators=(',', ':')).encode())
    def omit(table, slug):
        output['needs_expansion'] = True
        output['omitted'].append({'table': table, 'slug': slug})
        if size() > max_bytes:
            output['omitted'].pop()
            output['more_matches'] = True
    def place(table, item):
        if item['slug'] in selected[table]:
            return
        selected[table].add(item['slug'])
        item = memory_item(table, item, 'body_md', seen)
        if len(output[table]) >= top_k:
            output['more_matches'] = True
            omit(table, item['slug'])
            return
        output[table].append(item)
        if size() > max_bytes - 160:
            output[table].pop()
            omit(table, item['slug'])
    for table in tables:
        title = 'm.slug' if table == 'preferences' else 'm.title'
        body = ("coalesce(m.symptom_md,'') || char(10) || coalesce(m.workaround_md,'')"
                if table == 'known_problems' else "coalesce(m.body_md,'')")
        guard = " AND m.status='accepted'" if table == 'decisions' else " AND m.status='open'" if table == 'known_problems' else ''
        rows = conn.execute(f'SELECT m.slug,{title},{body},c.relevance FROM task_context_capsules c '
                            f'JOIN {table} m ON c.memory_id=m.id WHERE c.task_id=? AND c.memory_table=?'
                            + guard + ' ORDER BY c.relevance DESC,m.slug LIMIT ?', (row[0], table, top_k + 1)).fetchall()
        for slug, title, body, relevance in rows:
            place(table, dict(slug=slug, title=title or '', body_md=body, relevance=relevance, provenance='linked'))
    if discover:
        query = ' '.join(str(v or '') for v in row[2:])
        # Retrieve complete candidates before applying the shared output budget.
        found = request_context(conn, project, query, top_k, 100000)
        output['more_matches'] |= found['more_matches']
        output['needs_expansion'] |= found['needs_expansion']
        for table in tables:
            for item in found[table]:
                place(table, dict(slug=item['slug'], title=item['title'], body_md=item['body'],
                                  provenance='discovered', relevance=0))
        for item in found['omitted']:
            if item['slug'] not in selected[item['table']]:
                omit(item['table'], item['slug'])
    if size() > max_bytes:
        output['over_budget'] = True
    return output
