#!/usr/bin/env python3
"""Private backend of the runtime-owned skalling_workflow tool, not a shell API.

Actor/session come from ToolContext. This is process discipline, not protection
against the OS user who owns both the interpreter and database.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import sqlite3
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from skalling_classify import ROUTES, memory_blockers, normalize, project_db, readiness  # noqa: E402
from skalling_config import testing_config  # noqa: E402

ROLES = {'alex', 'pol', 'sol', 'teo', 'jhon', 'luz', 'pau', 'jes'}
# Verificador mecánico del carril trivial: no es un agente, es el comando de
# verificación del proyecto ejecutado por el motor sobre el candidato.
AUTO_VERIFIER = 'auto'
# Límite de cada comando de verificación: testing.timeout_seconds del
# proyecto (congelado en start), 15 min por defecto, 1 h como máximo. Antes
# era 110-120 s fijos y la batería real de un proyecto (7 min) no podía
# registrar evidencia (auditoría de c7517ea). El plugin espera más que esto.
DEFAULT_TIMEOUT = 900
MAX_TIMEOUT = 3600
# A delivery plus two focused corrections is enough to resolve a bounded task.
# A third rejected candidate is a signal to stop and re-scope instead of
# burning more model calls in the same loop.
MAX_DELIVERIES = 3
_ACTIVE = None  # comando en curso, para cancelarlo con todo su grupo
TERMINAL = {'completed', 'superseded'}
TRANSITIONS = {
    'clarify': ('pol', 'requested', 'clarified'),
    'plan': ('sol', 'clarified', 'planned'),
    'ready': ('sol', 'planned', 'implementation_ready'),
    'deliver': ('teo', 'implementation_ready', 'verification_ready'),
    'document': ('pau', 'quality_reviewed', 'documented'),
}
# Quién actúa y con qué acción en cada estado. Va en cada respuesta
# (next_step) y en cada rechazo: sin esto un modelo adivinaba el orden (caso
# real: creyó que Jhon aprueba antes de ready y probó acciones inexistentes).
NEXT_STEP = {
    'requested': 'Pol: clarify (alcance y aceptación acordados con el usuario)',
    'clarified': 'Sol: plan (diseño y rollback como evidencia)',
    'planned': 'Sol: ready con el plan aprobado. ' + '{plan_steps}',
    'implementation_ready': 'Teo: implementa con TDD y hace deliver (Alex le delega incluyendo el id del workflow)',
    'verification_ready': 'Jhon: oracle, después check y approve (o reject si falla). Jhon aprueba DESPUÉS del deliver de Teo',
    'quality_reviewed': 'Pau: document',
    'documented': 'Alex: complete',
    'completed': 'cerrado: para otro cambio, Alex hace start con un id nuevo',
    'superseded': 'reemplazado por otro workflow: seguí el nuevo',
}


def next_step(state):
    current = state.get('state')
    if current == 'blocked':
        return 'Alex: detener el ciclo; aclarar alcance o criterio y abrir otro workflow con supersedes'
    if current == 'implementation_ready' and state.get('last_rejection'):
        rejection = state['last_rejection']
        remaining = max(0, MAX_DELIVERIES - state.get('delivery_number', 0))
        return (f"Teo: corregir rechazo de {rejection['agent']} (entrega {rejection['delivery_number']}); "
                f"quedan {remaining} entrega(s), luego vuelve a entregar")
    if current == 'quality_reviewed' and state.get('execution_mode') == 'focused' and not state.get('memory_required'):
        return 'Alex: complete (sin conocimiento durable nuevo que documentar)'
    if current == 'verified':
        if state.get('risk') == 'low' and (state.get('verification') or {}).get('agent') == AUTO_VERIFIER:
            return ('Alex: complete si la evidencia cubre acceptance; si el check automático no cubre '
                    'el resultado pedido, delegar a Jhon oracle → check → approve sobre este workflow')
        return 'Luz: check y approve (riesgo alto)' if state.get('risk') == 'high' else 'Alex: complete'
    if current == 'verification_ready' and state.get('auto_verify'):
        return 'verificación automática del proyecto (la corre el motor al deliver); si falló, Teo corrige y vuelve a deliver'
    return NEXT_STEP.get(current, 'status para ver el estado').replace('{plan_steps}', PLAN_STEPS)


def next_action(state):
    """Machine-readable handoff; next_step remains for older prompt consumers."""
    current = state.get('state')
    routes = {
        'requested': ('pol', 'clarify'), 'clarified': ('sol', 'plan'),
        'planned': ('sol', 'ready'), 'implementation_ready': ('teo', 'deliver'),
        'verification_ready': ('jhon', 'oracle/check/approve'),
        'quality_reviewed': ('alex', 'complete'), 'verified': ('alex', 'complete'),
        'documented': ('alex', 'complete'), 'completed': ('done', 'none'),
        'superseded': ('done', 'follow_superseding_workflow'),
        'blocked': ('alex', 'stop_and_reclassify'),
    }
    if current == 'quality_reviewed' and state.get('risk') == 'high' and state.get('memory_required'):
        routes[current] = ('pau', 'document')
    elif current == 'quality_reviewed' and state.get('risk') == 'high' and state.get('execution_mode') != 'focused':
        routes[current] = ('pau', 'document')
    if current == 'verified' and state.get('risk') == 'high':
        routes[current] = ('luz', 'check/approve')
    if current == 'verification_ready' and state.get('auto_verify'):
        routes[current] = ('auto', 'verify')
    agent, action = routes.get(current, ('alex', 'status'))
    rejection = state.get('last_rejection') if current == 'implementation_ready' else None
    reason = rejection.get('reason') if rejection else None
    if current == 'verified' and state.get('risk') == 'low' and (state.get('verification') or {}).get('agent') == AUTO_VERIFIER:
        reason = 'Contrastar acceptance; si falta cobertura, Jhon abre oracle sobre este workflow antes del cierre.'
    return {
        'agent': agent, 'action': action,
        'reason': reason,
        'delivery_number': state.get('delivery_number', 0),
        'max_deliveries': MAX_DELIVERIES,
        'deliveries_remaining': max(0, MAX_DELIVERIES - state.get('delivery_number', 0)),
    }


def record_rejection(state, actor, reason):
    delivery_number = state.get('delivery_number', 0)
    state['rejection_count'] = state.get('rejection_count', 0) + 1
    state['last_rejection'] = {
        'agent': actor, 'reason': str(reason).strip()[:2000],
        'delivery_number': delivery_number, 'recorded_at': time.time(),
    }
    state['state'] = 'blocked' if delivery_number >= MAX_DELIVERIES else 'implementation_ready'
    state['oracle'] = None
    state['checks'] = []
    if state['state'] == 'blocked':
        state['blocked_reason'] = 'Se agotó el presupuesto de entregas; requiere aclarar alcance o criterio.'
    return state


DUMP_PATHSPEC = ':(exclude)db/teamdb/team.dump.sql'
SCOPE_EXCLUDES = [DUMP_PATHSPEC, ':(exclude).opencode', ':(exclude).git']


def scoped(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root) or any(p in {'.git', '.opencode'} for p in path.relative_to(root).parts):
        raise ValueError('Scope must stay in product files within the project')
    if path.name.startswith('.env') or path.suffix in {'.pem', '.db', '.sqlite', '.sqlite3'}:
        raise ValueError('Sensitive files require a separate authorized operation')
    return path


def base_head(root):
    out = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, capture_output=True, timeout=10)
    return out.stdout.decode().strip() if out.returncode == 0 else None


def classify_delivery(root, files, head):
    """Delivery identity beyond the bare digest: which declared files are
    additions, modifications or deletions relative to the revision the
    workflow started from -- so 'Jhon approved' names the exact candidate,
    not just a hash nobody can read back. Unchanged declared files (e.g. a
    test file Teo read but never touched) are omitted from all three lists."""
    added, modified, deleted = [], [], []
    for name in sorted(files):
        path = scoped(root, name)
        before = None
        if head:
            show = subprocess.run(['git', 'show', f'{head}:{name}'], cwd=root, capture_output=True, timeout=10)
            before = show.stdout if show.returncode == 0 else None
        after = path.read_bytes() if path.is_file() else None
        if after is not None and before is None:
            added.append(name)
        elif after is None and before is not None:
            deleted.append(name)
        elif after is not None and before is not None and after != before:
            modified.append(name)
    return {'added': added, 'modified': modified, 'deleted': deleted}


def fingerprint(root, files):
    digest = hashlib.sha256()
    for name in sorted(files):
        path = scoped(root, name)
        digest.update(name.encode() + b'\0')
        digest.update(path.read_bytes() if path.is_file() else b'<absent>')
        digest.update(b'\0')
    return digest.hexdigest()


def changed_paths(root):
    """Every path git sees as touched (tracked or not), regardless of stage."""
    out = subprocess.run(['git', 'status', '--porcelain=v1', '--untracked-files=all', '-z', '--', '.', *SCOPE_EXCLUDES],
                          cwd=root, capture_output=True, timeout=30)
    if out.returncode != 0:
        return set()
    tokens = out.stdout.decode('utf-8', 'replace').split('\0')
    paths, i = set(), 0
    while i < len(tokens) and tokens[i]:
        entry = tokens[i]
        paths.add(entry[3:])
        if entry[:2].strip('?').upper() in {'R', 'C'} or entry[0] in 'RC' or entry[1] in 'RC':
            i += 1  # rename/copy carries an extra NUL-separated "from" path
        i += 1
    return paths


def require_scope(root, files, head=None):
    changed = changed_paths(root)
    if inside_git(root):
        base = head or subprocess.check_output(['git', 'hash-object', '-t', 'tree', '--stdin'], cwd=root, input=b'').decode().strip()
        committed = subprocess.run(['git', 'diff', base, '--name-only', '--no-renames', '-z', '--', '.', *SCOPE_EXCLUDES],
                                   cwd=root, capture_output=True, timeout=30)
        require(committed.returncode == 0, 'Cannot inspect changes since workflow start')
        changed.update(p for p in committed.stdout.decode().split('\0') if p)
    extra = changed - set(files)
    require(not extra, f'Scope creep: {sorted(extra)} changed but not declared; use rescope')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def flag(payload, name):
    """Booleano estricto. bool("false") es True: un modelo que mandó
    "visual": "false" pedía un sistema de diseño que no hacía falta (prueba
    real con OpenCode 2.0.18)."""
    value = payload.get(name, False)
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.strip().lower() in {'true', 'false'}:
        return value.strip().lower() == 'true'
    if value in (None, 0, 1):
        return bool(value)
    raise ValueError(f'{name} debe ser true o false')


def file_list(payload, name='files'):
    files = payload.get(name, [])
    require(isinstance(files, list) and files and all(isinstance(f, str) and f.strip() for f in files),
            f'{name} debe ser una lista JSON de rutas, por ejemplo ["app.py", "test_app.py"]')
    return files


def staged_paths(root):
    out = subprocess.run(['git', 'diff', '--cached', '--name-only', '-z', '--no-renames', '--', '.', DUMP_PATHSPEC],
                         cwd=root, capture_output=True, timeout=30)
    if out.returncode != 0:
        raise ValueError('No se pudo leer el índice de Git; no se sella una aprobación a ciegas')
    return {p for p in out.stdout.decode('utf-8', 'replace').split('\0') if p}


def require_index_in_scope(root, files):
    """The receipt covers the WHOLE staged diff, so everything staged must be
    what was reviewed. require_scope() ignores .opencode (memory writes during
    the flow), but a staged .opencode/plugin.js or script is code nobody
    verified here: refuse instead of approving it by accident."""
    extra = staged_paths(root) - set(files)
    require(not extra, f'Staged files outside the reviewed scope: {sorted(extra)}. '
                       'Unstage them (git restore --staged) or review them in their own flow before completing')


def inside_git(root):
    out = subprocess.run(['git', 'rev-parse', '--is-inside-work-tree'], cwd=root, capture_output=True, timeout=10)
    return out.returncode == 0 and out.stdout.strip() == b'true'


def seal_receipt(db, root, identifier, files, verifier, digest, action='complete'):
    """Prepare a local commit or complete: stage exactly the reviewed files and
    seal a receipt with the same tree_hash algorithm scripts/hooks/git-gate.py
    checks at commit time. Fails closed: a completed workflow always leaves a
    receipt, or completion is refused (before, any Git failure silently left
    the workflow 'completed' without the evidence Git asks for)."""
    if not inside_git(root):
        return None
    require_index_in_scope(root, files)
    try:
        added = subprocess.run(['git', 'add', '-A', '--'] + list(files), cwd=root, capture_output=True, timeout=30)
        require(added.returncode == 0, 'git add falló al preparar el candidato: '
                + added.stderr.decode('utf-8', 'replace').strip())
        require_index_in_scope(root, files)
        # What got staged has to be what was verified (no edit slipped in
        # between the last fingerprint and git add).
        require(fingerprint(root, files) == digest, 'Candidate changed while staging; approval denied')
        diff = subprocess.run(['git', 'diff', '--cached', '--', '.', DUMP_PATHSPEC],
                               cwd=root, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError('No se pudo preparar el candidato en Git: ' + str(error))
    patch = diff.stdout.rstrip(b'\n')  # git-gate.py hashes the patch with the same rstrip
    require(diff.returncode == 0, 'No se pudo leer el diff preparado; no se sella a ciegas')
    if not patch.strip():
        return None  # nada que commitear: no hay candidato que sellar
    require(db.execute("SELECT 1 FROM pragma_table_info('receipts') WHERE name='tree_hash'").fetchone() is not None,
            'TeamDB sin receipts.tree_hash: correr bash scripts/teamdb-init.sh')
    tree_hash = hashlib.sha256(patch).hexdigest()[:16]
    db.execute("INSERT INTO receipts (id, task_id, agent, command, exit_code, output_summary, ts, tree_hash) "
               "VALUES (?,?,?,?,?,?,datetime('now'),?)",
               (f'rcpt_wf_{identifier}_{time.time_ns()}', identifier, verifier, f'skalling_workflow:{action}',
                0, json.dumps({'source': 'skalling_workflow', 'verifier': verifier}), tree_hash))
    return tree_hash


def invalidate_prepared_receipt(db, state):
    """Reopening review revokes a prepared approval, including a local commit's."""
    digest = state.pop('receipt_tree_hash', None)
    if not digest:
        return
    verifier = state.pop('prepared_receipt_verifier', None) or AUTO_VERIFIER
    db.execute("INSERT INTO receipts (id, task_id, agent, command, exit_code, output_summary, ts, tree_hash) "
               "VALUES (?,?,?,?,?,?,datetime('now'),?)",
               (f'rcpt_reopened_{time.time_ns()}', state['id'], verifier, 'skalling_workflow:review-reopened',
                1, 'Approval revoked: review or scope reopened; not a test failure', digest))


def configured_command(root, name):
    """testing.<name>.command disponible de .opencode/project.yaml (parser
    único: skalling_config). Vacío si no está disponible."""
    return testing_config(root / '.opencode/project.yaml').get(name, '')


def verification_timeout(root):
    value = testing_config(root / '.opencode/project.yaml').get('timeout_seconds', DEFAULT_TIMEOUT)
    return max(1, min(int(value), MAX_TIMEOUT))


def run_bounded(argv, root, env, timeout):
    """Corre el comando en su propio grupo de procesos: al vencer el plazo (o
    si el plugin cancela y llega SIGTERM) se termina el grupo entero, sin
    dejar pruebas huérfanas corriendo."""
    global _ACTIVE
    proc = subprocess.Popen(argv, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    _ACTIVE = proc
    try:
        output, _ = proc.communicate(timeout=timeout)
        return proc.returncode, output[-16000:].decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        proc.communicate()
        raise
    finally:
        _ACTIVE = None


def _kill_group(proc):
    if hasattr(os, 'killpg'):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    elif proc.poll() is None:
        proc.kill()


def _cancel(signum, _frame):
    if _ACTIVE is not None:
        _kill_group(_ACTIVE)
    sys.exit(128 + signum)


def verification_template(root):
    """Plantillas de verificación del proyecto, congeladas al iniciar el
    workflow (las lee Alex antes de que Teo toque nada: editar project.yaml
    después no cambia qué se ejecuta). testing.fast admite {files}."""
    return {'fast': configured_command(root, 'fast') or None, 'unit': configured_command(root, 'unit') or None}


def render_verification(template, files):
    template = template or {}
    if template.get('fast'):
        return ['bash', '-c', template['fast'].replace('{files}', shlex.join(sorted(files)))]
    return ['bash', '-c', template['unit']] if template.get('unit') else None


def auto_verification(root, files):
    """Only run the explicitly fast check without agent judgment.

    Unit suites can take minutes and may not be scoped to this change. If the
    project has no fast command, leave verification to Jhon so he can choose a
    focused check and escalate to the full suite when the impact warrants it.
    """
    return auto_verification_from_template(verification_template(root), files)


def auto_verification_from_template(template, files):
    if not template.get('fast'):
        return None
    return render_verification({'fast': template['fast']}, files)


def record_start_metrics(db, identifier, classification, intent, supersedes):
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'routing_decisions' in tables:
        db.execute("INSERT INTO routing_decisions (ts, user_intent, chosen_route, route_reason, agents_involved) "
                   "VALUES (datetime('now'), ?, ?, 'skalling_workflow start', ?)",
                   (intent or identifier, classification['route'], classification['agents']))
    if 'workflow_metrics' in tables:
        if supersedes:
            db.execute("UPDATE workflow_metrics SET outcome='superseded', completed_at=datetime('now') "
                       "WHERE request_id=? AND completed_at IS NULL", (supersedes,))
        db.execute("INSERT INTO workflow_metrics (request_id, risk_level, route, agents_count, started_at) "
                   "VALUES (?, ?, ?, ?, datetime('now')) ON CONFLICT(request_id) DO NOTHING",
                   (identifier, classification['risk'], classification['route'],
                    classification['agents'].count('→') + 1))
        db.execute('UPDATE workflow_metrics SET context_bytes=NULL, permission_prompts=NULL WHERE request_id=?', (identifier,))


def opencode_db():
    """Base de OpenCode (sesiones y mensajes con tokens). SKALLING_OPENCODE_DB
    la redefine (tests); si no, $XDG_DATA_HOME/opencode/opencode.db."""
    explicit = os.environ.get('SKALLING_OPENCODE_DB')
    if explicit:
        return Path(explicit)
    data = os.environ.get('XDG_DATA_HOME') or str(Path.home() / '.local/share')
    return Path(data) / 'opencode/opencode.db'


def runtime_usage(session, since, until):
    """Consumo real del pedido según OpenCode: respuestas de la sesión que lo
    inició y de sus subagentes, entre start y complete. None si no hay datos
    (otra versión de OpenCode, base ausente): medir no debe romper el cierre."""
    path = opencode_db()
    if not session or not path.is_file():
        return None
    try:
        con = sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True, timeout=5)
        try:
            tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if not {'session_v2', 'session_message'} <= tables:
                return None
            roots = session if isinstance(session, dict) else {session: since}
            windows = []
            for sid, started in roots.items():
                windows.extend((sid, int(started * 1000)))
            placeholders = ','.join('(?,?)' for _ in roots)
            rows = con.execute(f"""
                WITH RECURSIVE tree(id, since) AS (
                  VALUES {placeholders}
                  UNION SELECT s.id, tree.since FROM session_v2 s JOIN tree ON s.parent_id = tree.id),
                windows AS (SELECT id, MIN(since) since FROM tree GROUP BY id)
                SELECT m.session_id, m.data FROM session_message m JOIN windows ON m.session_id = windows.id
                WHERE m.type = 'assistant' AND m.time_created BETWEEN windows.since AND ?""",
                (*windows, int(until * 1000))).fetchall()
        finally:
            con.close()
    except sqlite3.Error:
        return None
    usage = {'tokens_input': 0, 'tokens_output': 0, 'tokens_cache_read': 0, 'cost': 0.0, 'agents': set(), 'sessions': set()}
    for session_id, raw in rows:
        try:
            data = json.loads(raw)
        except (TypeError, ValueError):
            continue
        tokens = data.get('tokens') or {}
        usage['tokens_input'] += int(tokens.get('input') or 0)
        usage['tokens_output'] += int(tokens.get('output') or 0) + int(tokens.get('reasoning') or 0)
        usage['tokens_cache_read'] += int((tokens.get('cache') or {}).get('read') or 0)
        usage['cost'] += float(data.get('cost') or 0)
        if data.get('agent'):
            usage['agents'].add(str(data['agent']))
        usage['sessions'].add(session_id)
    if not rows:
        return None
    usage['agents'] = sorted(usage['agents'])
    usage['sessions'] = len(usage['sessions'])
    return usage


def workflow_usage(db, state, now):
    roots = {state['start_session']: state['started_at']} if state.get('start_session') else {}
    for session, started in db.execute('SELECT session,MIN(ts) FROM agent_workflow_events WHERE request_id=? GROUP BY session', (state['id'],)):
        if session:
            roots[session] = min(roots.get(session, started), started)
    return runtime_usage(roots, state['started_at'], now)


def context_response(db, root, state, payload):
    """Deliver bounded memory at handoff; exact read keys belong to this caller.

    Never persist a shared 'seen' cache: another agent or a compacted session
    needs the full body again. Metrics measure bytes, never invented tokens.
    """
    from skalling_context import request_context, task_context
    seen = payload.get('context_seen', [])
    require(isinstance(seen, list) and len(seen) <= 200 and all(isinstance(k, str) for k in seen),
            'context_seen must be the read_keys whose bodies are still in your own context')
    if state.get('task'):
        plan, task = state['task'].split('/', 1)
        capsule = task_context(db, root, plan, task, seen=seen)
    else:
        capsule = request_context(db, root, state.get('intent') or state['acceptance'],
                                  visual=state.get('visual', False),
                                  options=[*state['files'], *('seen:' + k for k in seen)])
    if db.execute("SELECT 1 FROM sqlite_master WHERE name='workflow_metrics'").fetchone():
        size = len(json.dumps(capsule, ensure_ascii=False, separators=(',', ':')).encode())
        db.execute('UPDATE workflow_metrics SET context_bytes=COALESCE(context_bytes,0)+? WHERE request_id=?',
                   (size, state['id']))
        db.commit()
    return {**with_next_step(state), 'context': capsule}


def record_finish_metrics(db, identifier, duration_ms, handoffs, usage=None, retries=0):
    if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='workflow_metrics'").fetchone():
        return
    columns = {r[1] for r in db.execute("PRAGMA table_info(workflow_metrics)")}
    fields = {'outcome': 'success', 'duration_ms': duration_ms, 'handoffs': handoffs}
    if 'retries' in columns:
        fields['retries'] = retries
    if usage and 'tokens_input' in columns:
        fields.update(tokens_input=usage['tokens_input'], tokens_output=usage['tokens_output'],
                      tokens_cache_read=usage['tokens_cache_read'], cost=round(usage['cost'], 6),
                      agents_used=','.join(usage['agents']))
    sets = ', '.join(f'{k}=?' for k in fields)
    db.execute(f"UPDATE workflow_metrics SET {sets}, completed_at=datetime('now') "
               "WHERE request_id=? AND completed_at IS NULL", (*fields.values(), identifier))


PLAN_STEPS = ('1) bash ~/.config/opencode/scripts/teamdb-plan.sh crea el plan y devuelve su número (plan_id); '
              '2) bash ~/.config/opencode/scripts/teamdb-plan-approve.sh "$PWD" <plan_id> "<diseño>" "<aceptación>" '
              '"<aprobación del usuario>" lo aprueba con diseño; 3) ready con {"id", "plan_id": <ese número>, "evidence"}. '
              'El plan_id es el número real que devolvió el paso 1, nunca el de un ejemplo.')


def require_approved_plan(db, plan_id):
    require(plan_id not in (None, ''), 'Falta payload.plan_id. ' + PLAN_STEPS)
    row = db.execute("SELECT 1 FROM plans WHERE id=? AND status IN ('approved','in_progress') "
                     "AND length(design_md)>0", (plan_id,)).fetchone()
    if row is None:
        plans = db.execute("SELECT id, slug, status, length(coalesce(design_md,''))>0 FROM plans "
                           "ORDER BY id DESC LIMIT 5").fetchall()
        listed = '; '.join(f"id={i} {slug} [{status}{', con diseño' if design else ', sin diseño'}]"
                           for i, slug, status, design in plans) or 'ninguno todavía'
        raise ValueError(f'El plan {plan_id} no existe o no está aprobado con diseño. Planes en TeamDB: {listed}. '
                         + PLAN_STEPS)


def apply_pending_migrations(root):
    init_script = Path(__file__).resolve().parent / 'teamdb-init.sh'
    subprocess.run(['bash', str(init_script), str(root)], capture_output=True)


def ensure_tables(root, path):
    """agent_workflows/agent_workflow_events are versioned schema
    (sql/migrations/031_*), not something this script fabricates at runtime.
    Never connect() before checking existence: sqlite3.connect() creates an
    empty file as a side effect, and teamdb-init.sh treats an existing-but-
    schemaless file as a corrupt DB rather than a fresh one. Check first,
    then self-heal by applying pending migrations (same pattern
    teamdb-seal-receipt.sh uses for tree_hash) instead of silently creating
    undeclared tables."""
    if not path.exists():
        apply_pending_migrations(root)
    # Nunca crear una base vacía por accidente (connect() la crea): sin base,
    # teamdb-init.sh la trata como corrupta en vez de nueva.
    require(path.exists(), f'TeamDB no existe en {path}: correr /skalling-init (o bash scripts/teamdb-init.sh)')
    db = sqlite3.connect(path, timeout=10)
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
        db.close()
        apply_pending_migrations(root)
        db = sqlite3.connect(path, timeout=10)
        if not db.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
            raise ValueError('agent_workflows falta y teamdb-init.sh no pudo migrarla; correr bash scripts/teamdb-init.sh manualmente')
    return db


def save(db, identifier, actor, session, action, state, evidence, now):
    if actor != AUTO_VERIFIER and action not in {'feedback', 'status'}:
        state['handoffs'] += int(state.get('actor', actor) != actor)
        state['actor'] = actor
    state['updated_at'] = now
    if action in {'ready', 'deliver', 'check', 'approve', 'reject', 'reuse', 'status'}:
        state['usage'] = workflow_usage(db, state, now)
    if action != 'feedback' and db.execute("SELECT 1 FROM sqlite_master WHERE name='workflow_metrics'").fetchone():
        db.execute('UPDATE workflow_metrics SET duration_ms=?, handoffs=?, retries=? WHERE request_id=?',
                   (round((now - state['started_at']) * 1000), state['handoffs'],
                    state.get('rejection_count', 0), identifier))
        usage = state.get('usage')
        if usage:
            db.execute('UPDATE workflow_metrics SET tokens_input=?, tokens_output=?, tokens_cache_read=?, cost=? WHERE request_id=?',
                       (usage['tokens_input'], usage['tokens_output'], usage['tokens_cache_read'], usage['cost'], identifier))
    db.execute('INSERT INTO agent_workflows(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
               (identifier, json.dumps(state)))
    db.execute('INSERT INTO agent_workflow_events(request_id,actor,session,action,state,evidence,ts) VALUES(?,?,?,?,?,?,?)',
               (identifier, actor, session, action, state['state'], json.dumps(evidence), now))
    return state


def read(db, identifier):
    row = db.execute('SELECT body FROM agent_workflows WHERE id=?', (identifier,)).fetchone()
    return json.loads(row[0]) if row else None


def evidence_context(root):
    """Identity for reusing local evidence, never a cache of an approval.

    Hash every tracked/unignored file, environment and installed dependency
    metadata. Unknown/non-Git/oversized workspaces cannot reuse evidence.
    No environment values or source bytes are returned to the model.
    """
    try:
        listed = subprocess.run(['git', 'ls-files', '-co', '--exclude-standard', '-z'],
                                cwd=root, capture_output=True, check=True, timeout=10)
        names = sorted(set(listed.stdout.decode().split('\0')) - {''})
        if len(names) > 100000:
            return None
        digest = hashlib.sha256(json.dumps(sorted(os.environ.items())).encode())
        digest.update(sys.version.encode())
        digest.update(str(root).encode())
        for name in names:
            if name.startswith('.opencode/context/'):
                continue  # mutable workflow storage is not a product dependency
            path = root / name
            digest.update(name.encode() + b'\0')
            if path.is_symlink():
                return None  # external targets cannot be identified safely
            if path.is_file():
                with path.open('rb') as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(chunk)
            else:
                digest.update(b'<absent>')
        count = 0
        for folder in ('.venv', 'node_modules'):
            for directory, dirs, files in os.walk(root / folder):
                dirs.sort()
                for name in sorted(files):
                    path = Path(directory) / name
                    st = path.stat()
                    digest.update(str((str(path), st.st_size, st.st_mtime_ns, st.st_ctime_ns)).encode())
                    count += 1
                    if count > 100000:
                        return None
        return digest.hexdigest()
    except (OSError, subprocess.SubprocessError):
        return None


def reuse_evidence(db, root, actor, session, identifier, payload):
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and actor == 'luz' and state['state'] == 'verified',
            'Only Luz reuses independently executed evidence after Jhon approval')
    require(session != state.get('implementation_session'), 'Independent verifier session required')
    require(bool(str(payload.get('evidence', '')).strip()), 'Reuse requires a risk-specific justification')
    index = payload.get('check_index')
    require(type(index) is int and 0 <= index < len(state['checks']), 'Valid check_index required')
    source = state['checks'][index]
    require(source['agent'] == 'jhon' and source['exit_code'] == 0 and 'superseded_by' not in source,
            'Reuse requires successful Jhon evidence')
    require(fingerprint(root, state['files']) == source['digest'] == state['digest'], 'Candidate changed')
    require(source.get('reusable') is True, 'Source check must explicitly declare deterministic local inputs (reusable)')
    require(source.get('context') and source['context'] == evidence_context(root),
            'Evidence environment or workspace changed; run a fresh check')
    require(time.time() - source.get('finished_at', 0) <= 600, 'Evidence expired; run a fresh check')
    record = {k: v for k, v in source.items() if k != 'output'}
    record.update(agent=actor, session=session, reused_from=index, duration_ms=0,
                  method='review-of-independent-evidence', justification=payload['evidence'])
    state['checks'].append(record)
    state['verification'] = record
    save(db, identifier, actor, session, 'reuse', state, payload['evidence'], time.time())
    db.commit()
    return state


def check(db, root, actor, session, identifier, payload, request):
    """Runs the verification command OUTSIDE any held write lock: the command
    can take up to 120s and every other agent_workflows writer only waits 10s,
    so holding BEGIN IMMEDIATE across subprocess.run would lock them out.

    'check' only executes and records evidence; it never approves anything by
    itself. A command that exits 0 is one recorded observation, not proof the
    declared criteria are covered -- that judgment is a separate 'approve'
    action, so a single lucky/irrelevant green run (e.g. `true`) can't stand
    in for a real review, and Jhon/Luz can record several checks before
    deciding."""
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None, 'Unknown workflow')
    require(state['state'] not in TERMINAL, f"{state['state']} workflows are immutable")
    expected = 'verification_ready' if actor == 'jhon' else 'verified'
    require(actor in {'jhon', 'luz'} and state['state'] == expected, 'Check role/order invalid')
    require(bool(state['oracle']), 'Jhon must derive an oracle before checks')
    require(session != state['implementation_session'], 'Independent verifier session required')
    digest = state['digest']
    require(fingerprint(root, state['files']) == digest, 'Candidate changed; return to Teo')
    if flag(payload, 'configured'):
        argv = state.get('configured_verification')
        require(bool(argv), 'El proyecto no declara testing.fast ni testing.unit: usar un argv que tu política permita')
    else:
        argv = payload.get('argv')
        require(isinstance(argv, list) and argv and all(isinstance(v, str) and '\0' not in v for v in argv),
                'Command argv required (lista: ["python3", "test_app.py"]), o configured: true para el comando del proyecto')
    require(bool(payload.get('method')), 'Verification method required')
    require(bool(str(payload.get('criterion', '')).strip()),
            'Each check must name which declared criterion it exercises, not just run a command')
    context_before = evidence_context(root) if flag(payload, 'reusable') else None
    if context_before and payload.get('retry_of') is None:
        for index in range(len(state['checks']) - 1, -1, -1):
            previous = state['checks'][index]
            if previous['argv'] == argv and previous['exit_code'] != 0 and 'superseded_by' not in previous:
                break
            if (previous.get('reusable') and previous.get('context') == context_before
                    and previous['agent'] == actor and previous['session'] == session
                    and previous['argv'] == argv and previous['digest'] == digest
                    and previous['criterion'] == payload['criterion'] and previous['method'] == payload['method']
                    and previous['exit_code'] == 0 and 'superseded_by' not in previous
                    and time.time() - previous.get('finished_at', 0) <= 600):
                reused = {**previous, 'reused_from': index, 'duration_ms': 0}
                state['checks'].append(reused)
                state['verification'] = reused
                save(db, identifier, actor, session, 'reuse', state, 'Unchanged deterministic check', time.time())
                db.commit()
                return state
    save(db, identifier, actor, session, 'check-started', state, {'argv': argv, 'criterion': payload['criterion']}, time.time())
    db.commit()  # release the write lock before the potentially slow command

    # Native tool wrapper obtains OpenCode permission for this exact command.
    # El comando sabe quién lo corre y que la evidencia la registra el motor
    # (skalling-review.sh no sella por su cuenta dentro de un check).
    env = {**os.environ, 'SKALLING_RUNTIME_AGENT': actor, 'SKALLING_WORKFLOW_CHECK': '1'}
    timeout = state.get('verification_timeout') or DEFAULT_TIMEOUT
    started = time.monotonic()
    try:
        exit_code, output = run_bounded(argv, root, env, timeout)
    except subprocess.TimeoutExpired:
        db.execute('BEGIN IMMEDIATE')
        current = read(db, identifier)
        save(db, identifier, actor, session, 'check-timeout', current,
             {'argv': argv, 'duration_ms': round((time.monotonic() - started) * 1000),
              'failure_kind': 'timeout'}, time.time())
        db.commit()
        # Un timeout queda en eventos; no se transforma en fallo del producto.
        raise ValueError(f'El check superó {timeout}s y se canceló sin registrarse; subir '
                         'testing.timeout_seconds o usar un comando más acotado')

    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == expected, 'Workflow changed during verification; retry check')
    require(fingerprint(root, state['files']) == digest == state['digest'], 'Verification changed candidate; approval denied')
    verification = {'agent': actor, 'session': session, 'method': payload['method'], 'argv': argv,
                     'criterion': payload['criterion'], 'exit_code': exit_code, 'digest': digest, 'output': output,
                     'model': request.get('model'), 'independence': 'context-and-method; model diversity unverified'}
    verification.update(duration_ms=round((time.monotonic() - started) * 1000), finished_at=time.time())
    verification['reusable'] = flag(payload, 'reusable')
    context_after = evidence_context(root) if context_before else None
    verification['context'] = context_before if context_before == context_after else None
    retry = payload.get('retry_of')
    if retry is not None:
        require(type(retry) is int and 0 <= retry < len(state['checks']), 'Valid retry_of required')
        prior = state['checks'][retry]
        require(payload.get('failure_kind') in {'infrastructure', 'flaky'} and
                bool(str(payload.get('evidence', '')).strip()), 'Retry needs failure classification and evidence')
        require(prior['agent'] == actor and prior['digest'] == digest and prior['argv'] == argv
                and prior['exit_code'] != 0 and 'superseded_by' not in prior,
                'Retry must replace your unresolved failing check on this candidate with the same command')
        require(sum(c.get('retry_of') is not None for c in state['checks']) < 2, 'Retry budget exhausted')
        verification['retry_of'] = retry
        verification['failure_kind'] = payload['failure_kind']
        if exit_code == 0:
            cursor = retry
            while cursor is not None:
                replaced = state['checks'][cursor]
                replaced['superseded_by'] = len(state['checks'])
                cursor = replaced.get('retry_of')
    state['checks'].append(verification)
    state['verification'] = verification
    now = time.time()
    state = save(db, identifier, actor, session, 'check', state, payload.get('evidence', ''), now)
    db.commit()
    return state


def auto_verify(db, root, identifier, session):
    """Carril trivial: tras la entrega de Teo, el motor ejecuta el comando de
    verificación congelado al iniciar y registra el resultado como evidencia
    de AUTO_VERIFIER. Pasa -> verified (Alex completa). Falla -> vuelve a
    Teo con la salida. Sin veredicto (timeout) -> queda para Jhon."""
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == 'verification_ready' and state.get('auto_verify'),
            'Auto verification not applicable')
    digest, argv = state['digest'], state['auto_verify']
    db.commit()
    env = {**os.environ, 'SKALLING_RUNTIME_AGENT': AUTO_VERIFIER, 'SKALLING_WORKFLOW_CHECK': '1'}
    timeout = state.get('verification_timeout') or DEFAULT_TIMEOUT
    started = time.monotonic()
    try:
        exit_code, output = run_bounded(argv, root, env, timeout)
    except subprocess.TimeoutExpired:
        exit_code, output = None, f'Sin veredicto: la verificación superó {timeout}s'
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == 'verification_ready', 'Workflow changed during auto verification')
    require(fingerprint(root, state['files']) == digest == state['digest'], 'Verification changed candidate; approval denied')
    verification = {'agent': AUTO_VERIFIER, 'session': session, 'method': 'configured-verification', 'argv': argv,
                    'criterion': 'Regresión configurada del proyecto; cobertura del pedido por contrastar',
                    'exit_code': exit_code, 'digest': digest, 'output': output,
                    'independence': 'comando del proyecto congelado al iniciar; no lo elige quien implementa'}
    verification['duration_ms'] = round((time.monotonic() - started) * 1000)
    state['checks'].append(verification)
    state['verification'] = verification
    if exit_code == 0:
        state['state'] = 'verified'
        evidence = 'verificación configurada del proyecto pasó sobre el candidato entregado'
    elif exit_code in {None, 124, 126, 127}:
        verification['failure_kind'] = 'infrastructure'
        state['auto_verify'] = None  # que Jhon decida cómo verificar
        evidence = output + '; queda para Jhon'
    else:
        record_rejection(state, AUTO_VERIFIER, output or 'configured verification failed')
        evidence = ('verificación configurada falló; vuelve a Teo' if state['state'] == 'implementation_ready'
                    else 'verificación configurada falló y se agotó el presupuesto; detener para reclasificar')
    state = save(db, identifier, AUTO_VERIFIER, session, 'auto-verify', state, evidence, time.time())
    db.commit()
    return state


def objective(payload):
    intent = payload.get('intent')
    require(isinstance(intent, str) and bool(intent.strip()), 'Original user intent required')
    outcomes = payload.get('outcomes', [{'id': 'acceptance', 'expected': payload['acceptance']}])
    require(isinstance(outcomes, list) and 1 <= len(outcomes) <= 30, 'One to thirty observable outcomes required')
    seen = set()
    for item in outcomes:
        require(isinstance(item, dict) and isinstance(item.get('id'), str)
                and bool(re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', item['id']))
                and item['id'] not in seen and isinstance(item.get('expected'), str)
                and bool(item['expected'].strip()), 'Unique outcome ids and observable expected results required')
        seen.add(item['id'])
    return intent, outcomes


def cover_outcomes(state, payload, actor):
    """Enforce traceability, not a claim that prose proves semantic correctness."""
    outcomes = state.get('outcomes') or [{'id': 'acceptance', 'expected': state['acceptance']}]
    coverage = payload.get('coverage', state.get('coverage'))
    require(isinstance(coverage, list), 'Outcome coverage required: outcome_id, check_index, observation')
    require(len(coverage) == len(outcomes) and all(isinstance(c, dict) and isinstance(c.get('outcome_id'), str) for c in coverage)
            and {c.get('outcome_id') for c in coverage} == {o['id'] for o in outcomes},
            'Every outcome must have exactly one evidence mapping')
    for entry in coverage:
        index = entry.get('check_index')
        require(type(index) is int and 0 <= index < len(state['checks']), 'Coverage requires a real check_index')
        check = state['checks'][index]
        require(check['exit_code'] == 0 and check['digest'] == state['digest']
                and 'superseded_by' not in check, 'Coverage evidence must pass on the current candidate')
        if actor in {'jhon', 'luz'}:
            require(check['agent'] == actor, 'Reviewer must map their own independently recorded evidence')
        require(isinstance(entry.get('observation'), str) and entry['observation'].strip(),
                'Coverage requires the observed result, not only an exit code')
    state['coverage'] = coverage


def record_feedback(db, state, payload, actor, session, now):
    require(actor == 'alex', 'Only Alex records explicit user feedback')
    key, kind, evidence = payload.get('feedback_id'), payload.get('kind'), payload.get('evidence')
    require(isinstance(key, str) and 0 < len(key) <= 200, 'Stable user message feedback_id required')
    require(kind in {'accepted', 'correction', 'scope_change', 'new_task'}, 'Explicit feedback kind required')
    require(isinstance(evidence, str) and bool(evidence.strip()), 'User feedback evidence required')
    feedback = state.setdefault('feedback', [])
    previous = next((x for x in feedback if x['id'] == key), None)
    item = {'id': key, 'kind': kind, 'evidence': evidence}
    require(previous is None or previous == item, 'Feedback id already recorded with different content')
    if previous:
        return state
    feedback.append(item)
    state['human_corrections'] = sum(x['kind'] == 'correction' for x in feedback)
    state['user_acceptance'] = kind if kind in {'accepted', 'correction'} else state.get('user_acceptance')
    return save(db, state['id'], actor, session, 'feedback', state, item, now)


def operate(request):
    root = Path(request['project']).resolve()
    actor, session = request['actor'].lower(), request['session']
    require(actor in ROLES and bool(session), 'Runtime agent/session required')
    action, payload = request['action'], request.get('payload', {})
    identifier = payload['id']
    require(isinstance(identifier, str) and 0 < len(identifier) <= 200, 'Invalid request id')
    # En un worktree la memoria es la del repositorio principal (mismo
    # criterio que los helpers); los archivos son los de este checkout.
    path = project_db(root)
    require(path.parent.is_dir(), 'Initialize project context first')
    db = ensure_tables(root, path)
    try:
        if action == 'feedback':
            db.execute('BEGIN IMMEDIATE')
            state = read(db, identifier)
            require(state is not None, 'Unknown workflow')
            state = record_feedback(db, state, payload, actor, session, time.time())
            db.commit()
            return with_next_step(state)
        if action == 'status':
            state = read(db, identifier)
            require(state is not None, 'Unknown workflow')
            if state['state'] not in TERMINAL:
                now = time.time()
                save(db, identifier, actor, session, 'status', state, '', now)
                db.commit()
            return context_response(db, root, state, payload)
        if action == 'evidence':
            state = read(db, identifier)
            require(state is not None, 'Unknown workflow')
            index = payload.get('check_index')
            require(type(index) is int and 0 <= index < len(state['checks']), 'Valid check_index required')
            return {'id': identifier, 'check_index': index, 'check': state['checks'][index]}
        if action == 'reuse':
            return with_next_step(reuse_evidence(db, root, actor, session, identifier, payload))
        if action == 'check':
            return with_next_step(check(db, root, actor, session, identifier, payload, request))

        db.execute('BEGIN IMMEDIATE')
        state = read(db, identifier)
        now = time.time()
        evidence = payload.get('evidence', '')
        if action == 'start':
            require(actor == 'alex' and state is None, 'Only Alex creates a new workflow; id cannot be reused')
            # Mismas reglas que skalling-route.sh (skalling_classify): una sola
            # autoridad decide si se implementa y por qué ruta.
            classification = normalize('code', payload.get('risk'), payload.get('scope', 'unknown'),
                                       payload.get('clarity', 'clear'), payload.get('decision', 'none'),
                                       flag(payload, 'sensitive'), flag(payload, 'visual'))
            require(not classification['needs_user_decision'],
                    'Pending decisions require explicit user resolution first')
            require(classification['scope'] != 'unknown', 'Known scope required')
            ready_state = readiness(path)
            require(ready_state in {'initialized', 'ready'},
                    f'Proyecto sin contexto inicial (readiness={ready_state}): ruta DISCOVERY (Jes → Pol) antes de implementar')
            blockers = memory_blockers(path, classification['visual'])
            require(not blockers, '; '.join(blockers))
            files = file_list(payload)
            require(bool(str(payload.get('acceptance', '')).strip()), 'Observable acceptance required')
            require(bool(str(payload.get('reuse', '')).strip()),
                    'Reuse strategy required: qué componente/patrón existente se reutiliza')
            intent, outcomes = objective(payload)
            fingerprint(root, files)
            supersedes = payload.get('supersedes')
            if supersedes:
                previous = read(db, supersedes)
                require(previous is not None and previous['state'] not in TERMINAL,
                        'supersedes debe nombrar un workflow abierto')
                previous['state'] = 'superseded'
                invalidate_prepared_receipt(db, previous)
                previous['superseded_by'] = identifier
                save(db, supersedes, actor, session, 'superseded', previous, f'reemplazado por {identifier}', now)
            risk = classification['risk']
            task = payload.get('task')
            require(task is None or (isinstance(task, str) and task.count('/') == 1), 'task debe ser "plan-slug/task-slug"')
            state = {'id': identifier, 'intent': intent, 'outcomes': outcomes, 'coverage': None, 'risk': risk, 'files': files, 'acceptance': payload['acceptance'],
                     'reuse': payload['reuse'], 'task': task, 'visual': classification['visual'],
                     'state': 'implementation_ready' if risk == 'low' else ('clarified' if risk == 'medium' else 'requested'),
                     'route': classification['route'], 'agents': classification['agents'],
                     'started_at': now, 'handoffs': 0, 'checks': [], 'oracle': None, 'digest': None,
                     'rejection_count': 0,
                     'base_head': base_head(root), 'delivery_number': 0, 'delivery': None,
                     'verification_template': verification_template(root),
                     'verification_timeout': verification_timeout(root),
                     'auto_verify': auto_verification(root, files) if risk == 'low' else None,
                     # Comando de verificación que declara el proyecto, congelado
                     # acá: Jhon/Luz lo corren con check {configured: true} sin
                     # pedir permiso (en OpenCode v2 un plugin no puede pedirlo).
                     'configured_verification': render_verification(verification_template(root), files),
                     'supersedes': supersedes, 'start_session': session}
            # A forgotten mode must not silently send a clear local request
            # through the expensive staged chain. The model can still opt into
            # staged explicitly, and plans/tasks remain staged by default.
            mode = payload.get('execution_mode')
            if mode is None:
                mode = ('focused' if classification['risk'] in {'low', 'medium'}
                        and classification['scope'] == 'local'
                        and payload.get('clarity', 'clear') == 'clear'
                        and not flag(payload, 'sensitive')
                        and not flag(payload, 'planning_required')
                        and not flag(payload, 'memory_required') and not task else 'staged')
            require(mode in {'staged', 'focused'}, 'execution_mode must be focused or staged')
            if mode == 'focused':
                require(classification['scope'] == 'local'
                        and payload.get('clarity', 'clear') == 'clear'
                        and not flag(payload, 'sensitive')
                        and not flag(payload, 'planning_required')
                        and not flag(payload, 'memory_required') and not task,
                        'focused requires a clear, local, non-sensitive task with no plan, task, or memory work')
            state['execution_mode'] = mode
            state['memory_required'] = flag(payload, 'memory_required')
            state['planning_required'] = flag(payload, 'planning_required')
            if mode == 'focused':
                state['state'] = 'clarified' if flag(payload, 'planning_required') else 'implementation_ready'
                state['route'] = 'FAST-TRACK' if risk == 'low' else 'DIRECT'
                state['agents'] = 'Alex → ' + ('Sol → ' if flag(payload, 'planning_required') else '') + 'Teo'
                if risk != 'low':
                    state['agents'] += ' → Jhon'
                if risk == 'high':
                    state['agents'] += ' → Luz' + (' → Pau' if state['memory_required'] else '')
                classification = {**classification, 'route': state['route'], 'agents': state['agents']}
            record_start_metrics(db, identifier, classification, payload.get('intent'), supersedes)
        else:
            require(state is not None, 'Unknown workflow')
            require(state['state'] not in TERMINAL or (state['state'] == 'completed' and action == 'prepare_commit'),
                    f"{state['state']} workflows are immutable")
            if action in TRANSITIONS:
                owner, previous, target = TRANSITIONS[action]
                require(actor == owner and state['state'] == previous, f'{action} requires {owner} in {previous}')
                require(action == 'deliver' or bool(str(evidence).strip()), 'Transition evidence required')
                if action == 'ready':
                    require_approved_plan(db, payload.get('plan_id'))
                    state['plan_id'] = payload['plan_id']
                if action == 'deliver':
                    require_scope(root, state['files'], state.get('base_head'))
                    invalidate_prepared_receipt(db, state)
                    state['digest'] = fingerprint(root, state['files'])
                    state['implementation_session'] = session
                    state['oracle'] = None
                    state['checks'] = []
                    state['coverage'] = None
                    state['delivery_number'] += 1
                    state['delivery'] = {**classify_delivery(root, state['files'], state['base_head']),
                                          'digest': state['digest'], 'delivery_number': state['delivery_number'],
                                          'base_head': state['base_head']}
                state['state'] = target
            elif action == 'rescope':
                require(actor == 'teo' and state['state'] in {'implementation_ready', 'verification_ready'},
                        'Only Teo widens scope, and only before an approval is trusted')
                added = payload.get('files', [])
                require(isinstance(added, list) and added and all(isinstance(f, str) for f in added), 'Enumerated files required')
                require(bool(str(evidence).strip()),
                        'Rescope requires evidence explaining the additional files. '
                        f"Estado del workflow: {state['state']}. "
                        'Siguiente paso: Teo: reintenta rescope con el mismo id, files y '
                        'evidence (texto que relaciona los archivos nuevos con el objetivo). '
                        'Completa la justificación técnica con lo observado; no pidas al usuario '
                        'rellenar este campo. Si cambia una decisión de producto, consúltala con Alex')
                widened = sorted(set(state['files']) | set(added))
                require(widened != state['files'], 'Rescope must add at least one new file')
                for name in widened:
                    scoped(root, name)
                # Módulo = carpeta de primer nivel; los archivos de la raíz
                # comparten el módulo raíz ('.').
                module = lambda f: Path(f).parts[0] if len(Path(f).parts) > 1 else '.'
                top_before = {module(f) for f in state['files']}
                top_after = {module(f) for f in widened}
                risk = state['risk']
                if flag(payload, 'sensitive'):
                    risk = 'high'
                elif (top_after - top_before) and risk == 'low':
                    risk = 'medium'
                escalated = risk != state['risk']
                invalidate_prepared_receipt(db, state)
                state['files'] = widened
                state['digest'] = None
                state['oracle'] = None
                state['checks'] = []
                state['verification'] = None
                state['coverage'] = None
                template = state.get('verification_template')
                state['configured_verification'] = render_verification(template, widened)
                if escalated:
                    # Cambiar la etiqueta no alcanza (auditoría de c7517ea): la
                    # nueva ruta exige sus fases y su evidencia. El plan
                    # anterior no cubría este alcance y lo trivial deja de
                    # verificarse solo.
                    state['risk'] = risk
                    state['route'], state['agents'], _ = ROUTES[risk]
                    state['state'] = 'clarified' if risk == 'medium' else 'requested'
                    state['auto_verify'] = None
                    state['plan_id'] = None
                    state['escalated_from_rescope'] = True
                else:
                    # Mismo riesgo: el comando congelado se vuelve a armar con
                    # los archivos nuevos ({files}) para que los cubra.
                    state['auto_verify'] = (auto_verification_from_template(template, widened)
                                            if risk == 'low' and not state.get('independent_review_required') else None)
                    state['state'] = 'implementation_ready'
            elif action == 'oracle':
                auto_passed = (state['state'] == 'verified' and state['risk'] == 'low'
                               and (state.get('verification') or {}).get('agent') == AUTO_VERIFIER)
                require(actor == 'jhon' and (state['state'] == 'verification_ready' or auto_passed),
                        'Only Jhon prepares the oracle before verification or after an automatic check')
                require(session != state['implementation_session'], 'Independent verifier session required')
                fields = ('expected', 'negative', 'invariant', 'refutation')
                require(all(isinstance(payload.get(f), str) and payload[f].strip() for f in fields), 'Complete independent oracle required')
                require(state['oracle'] is None, 'Oracle is frozen for this delivery')
                if auto_passed:
                    invalidate_prepared_receipt(db, state)
                state['oracle'] = {f: payload[f] for f in fields}
                state['coverage'] = None
                # A generic green check can miss the requested behavior. Permit
                # an independent review without discarding valid observations
                # or sending the implementation through planning again.
                state['state'] = 'verification_ready'
                state['auto_verify'] = None
                state['independent_review_required'] = True
            elif action == 'approve':
                require(actor in {'jhon', 'luz'}, 'Only Jhon or Luz approve')
                target = {'jhon': 'verified', 'luz': 'quality_reviewed'}[actor]
                source = {'jhon': 'verification_ready', 'luz': 'verified'}[actor]
                require(state['state'] == source, f'{actor} approves from {source}, not {state["state"]}')
                require(bool(str(evidence).strip()),
                        'Approval requires evidence that the declared criteria are covered, not just a green exit code')
                if actor == 'luz':
                    require(isinstance(payload.get('findings'), str) and payload['findings'].strip(),
                            'Luz must record an explicit risk verdict, not just a command exit code')
                relevant = [c for c in state['checks'] if c['agent'] == actor and c['digest'] == state['digest'] and 'superseded_by' not in c]
                require(relevant, f'{actor} must record at least one check on the current candidate before approving')
                require(all(c['exit_code'] == 0 for c in relevant),
                        'A failing check is on record for this candidate; a later passing one does not erase it')
                if actor == 'luz':
                    state['quality_findings'] = payload['findings']
                cover_outcomes(state, payload, actor)
                state['state'] = target
            elif action == 'reject':
                require(actor in {'jhon', 'luz'} and state['state'] in {'verification_ready', 'verified', 'quality_reviewed'}, 'Invalid rejection')
                require(bool(str(evidence).strip()), 'Rejection requires diagnostic evidence')
                reason = payload.get('findings') or evidence
                invalidate_prepared_receipt(db, state)
                record_rejection(state, actor, reason)
            elif action == 'prepare_commit':
                require(actor in {'teo', 'jhon', 'luz'}, 'Only Teo, Jhon or Luz prepare autonomous local commits')
                require(inside_git(root), 'Local commits require a Git repository')
                approved = {'quality_reviewed', 'documented'} if state['risk'] == 'high' else {'verified'}
                approved.add('completed')
                require(state['state'] in approved, 'Local commit requires the verification for this risk level')
                require_scope(root, state['files'], state.get('base_head'))
                require_index_in_scope(root, state['files'])
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed after verification')
                cover_outcomes(state, payload, 'delivery')
                verifier = (state.get('verification') or {}).get('agent', 'jhon')
                receipt = seal_receipt(db, root, identifier, state['files'], verifier, state['digest'], 'prepare_commit')
                state['receipt_tree_hash'] = receipt or state.get('receipt_tree_hash')
                state['prepared_receipt_verifier'] = verifier
                evidence = 'Verified local unit staged and sealed; git commit is allowed, push needs user authorization'
            elif action == 'complete':
                require(actor == 'alex', 'Only Alex completes a workflow')
                expected = ('quality_reviewed' if state.get('execution_mode') == 'focused' and not state.get('memory_required')
                            else 'documented') if state['risk'] == 'high' else 'verified'
                require(state['state'] == expected, f'Completion requires {expected}')
                require_scope(root, state['files'], state.get('base_head'))
                require_index_in_scope(root, state['files'])
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed after verification')
                state['state'] = 'completed'
                state['completed_at'] = now
                state['duration_ms'] = round((now - state['started_at']) * 1000)
                cover_outcomes(state, payload, 'delivery')
                verifier = (state.get('verification') or {}).get('agent', 'jhon')
                state['receipt_tree_hash'] = (seal_receipt(db, root, identifier, state['files'], verifier, state['digest'])
                                              or state.get('receipt_tree_hash'))
                state['usage'] = workflow_usage(db, state, now)
                record_finish_metrics(db, identifier, state['duration_ms'], state['handoffs'], state['usage'],
                                      state.get('rejection_count', 0))
            else:
                raise ValueError('Unknown workflow action')
        state = save(db, identifier, actor, session, action, state, evidence, now)
        db.commit()
        if action == 'deliver' and state['state'] == 'verification_ready' and state.get('auto_verify'):
            state = auto_verify(db, root, identifier, session)
        return context_response(db, root, state, payload) if action in {'start', 'ready'} else with_next_step(state)
    except ValueError as error:
        # El rechazo dice además en qué estado está el pedido y quién sigue.
        db.rollback()
        current = read(db, identifier)
        if current is not None and 'Siguiente paso:' not in str(error):
            raise ValueError(f"{error}. Estado del workflow: {current['state']}. "
                             f"Siguiente paso: {next_step(current)}") from None
        raise
    finally:
        db.close()


def with_next_step(state):
    if isinstance(state, dict) and 'state' in state:
        return {**state, 'next_step': next_step(state)}
    return state


def public_response(state):
    """Small default response; evidence action retrieves a single full log."""
    if not isinstance(state, dict) or 'state' not in state:
        return state
    fields = ('id', 'state', 'risk', 'route', 'agents', 'files', 'acceptance', 'reuse',
              'task', 'plan_id', 'digest', 'delivery_number', 'next_step', 'receipt_tree_hash',
              'duration_ms', 'execution_mode', 'memory_required', 'planning_required',
              'last_rejection', 'blocked_reason', 'rejection_count', 'oracle',
              'intent', 'outcomes', 'coverage', 'human_corrections', 'user_acceptance', 'usage', 'auto_verify', 'context')
    response = {key: state[key] for key in fields if key in state}
    response['next_step'] = next_step(state)
    response['recommended_action'] = next_action(state)
    commit_states = {'quality_reviewed', 'documented', 'completed'} if state.get('risk') == 'high' else {'verified', 'completed'}
    if state['state'] in commit_states:
        response['local_commit'] = {
            'ready': True, 'agents': ['teo', 'jhon', 'luz'], 'prepare_action': 'prepare_commit',
            'then': 'git commit -m "mensaje"', 'repeat_checks': False, 'push': 'user_approval',
            'coverage_required': not bool(state.get('coverage')),
        }
    response['check_count'] = len(state.get('checks', []))
    response['checks'] = [{**{k: c[k] for k in ('agent', 'exit_code', 'argv', 'duration_ms',
                        'criterion', 'method', 'reused_from', 'superseded_by', 'failure_kind') if k in c}, 'check_index': i}
                         for i, c in enumerate(state.get('checks', []))]
    last = state.get('verification') or {}
    if last.get('exit_code', 0) != 0:
        response['failure_output'] = last.get('output', '')[-2000:]
    return response


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, _cancel)
    signal.signal(signal.SIGINT, _cancel)
    try:
        print(json.dumps(public_response(operate(json.load(sys.stdin)))))
    except (ValueError, KeyError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
