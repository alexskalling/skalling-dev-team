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
    if current == 'verified':
        return 'Luz: check y approve (riesgo alto)' if state.get('risk') == 'high' else 'Alex: complete'
    if current == 'verification_ready' and state.get('auto_verify'):
        return 'verificación automática del proyecto (la corre el motor al deliver); si falló, Teo corrige y vuelve a deliver'
    return NEXT_STEP.get(current, 'status para ver el estado').replace('{plan_steps}', PLAN_STEPS)


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


def require_scope(root, files):
    extra = changed_paths(root) - set(files)
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


def seal_receipt(db, root, identifier, files, verifier, digest):
    """Bridge to the Git-facing approval: stage exactly the reviewed files and
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
               (f'rcpt_wf_{identifier}_{int(time.time())}', identifier, verifier, 'skalling_workflow:complete',
                0, json.dumps({'source': 'skalling_workflow', 'verifier': verifier}), tree_hash))
    return tree_hash


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
    return render_verification(verification_template(root), files)


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
            rows = con.execute("""
                WITH RECURSIVE tree(id) AS (
                  SELECT id FROM session_v2 WHERE id = ?
                  UNION SELECT s.id FROM session_v2 s JOIN tree ON s.parent_id = tree.id)
                SELECT m.session_id, m.data FROM session_message m JOIN tree ON m.session_id = tree.id
                WHERE m.type = 'assistant' AND m.time_created BETWEEN ? AND ?""",
                (session, int(since * 1000), int(until * 1000))).fetchall()
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
    if actor != AUTO_VERIFIER:
        state['handoffs'] += int(state.get('actor', actor) != actor)
        state['actor'] = actor
    state['updated_at'] = now
    db.execute('INSERT INTO agent_workflows(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
               (identifier, json.dumps(state)))
    db.execute('INSERT INTO agent_workflow_events(request_id,actor,session,action,state,evidence,ts) VALUES(?,?,?,?,?,?,?)',
               (identifier, actor, session, action, state['state'], json.dumps(evidence), now))
    return state


def read(db, identifier):
    row = db.execute('SELECT body FROM agent_workflows WHERE id=?', (identifier,)).fetchone()
    return json.loads(row[0]) if row else None


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
    db.commit()  # release the write lock before the potentially slow command

    # Native tool wrapper obtains OpenCode permission for this exact command.
    # El comando sabe quién lo corre y que la evidencia la registra el motor
    # (skalling-review.sh no sella por su cuenta dentro de un check).
    env = {**os.environ, 'SKALLING_RUNTIME_AGENT': actor, 'SKALLING_WORKFLOW_CHECK': '1'}
    timeout = state.get('verification_timeout') or DEFAULT_TIMEOUT
    try:
        exit_code, output = run_bounded(argv, root, env, timeout)
    except subprocess.TimeoutExpired:
        # Sin veredicto no es un fallo del candidato: no se registra (un check
        # fallido registrado bloquearía la aprobación de toda la entrega).
        raise ValueError(f'El check superó {timeout}s y se canceló sin registrarse; subir '
                         'testing.timeout_seconds o usar un comando más acotado')

    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == expected, 'Workflow changed during verification; retry check')
    require(fingerprint(root, state['files']) == digest == state['digest'], 'Verification changed candidate; approval denied')
    verification = {'agent': actor, 'session': session, 'method': payload['method'], 'argv': argv,
                     'criterion': payload['criterion'], 'exit_code': exit_code, 'digest': digest, 'output': output,
                     'model': request.get('model'), 'independence': 'context-and-method; model diversity unverified'}
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
    try:
        exit_code, output = run_bounded(argv, root, env, timeout)
    except subprocess.TimeoutExpired:
        exit_code, output = None, f'Sin veredicto: la verificación superó {timeout}s'
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == 'verification_ready', 'Workflow changed during auto verification')
    require(fingerprint(root, state['files']) == digest == state['digest'], 'Verification changed candidate; approval denied')
    verification = {'agent': AUTO_VERIFIER, 'session': session, 'method': 'configured-verification', 'argv': argv,
                    'criterion': state['acceptance'], 'exit_code': exit_code, 'digest': digest, 'output': output,
                    'independence': 'comando del proyecto congelado al iniciar; no lo elige quien implementa'}
    state['checks'].append(verification)
    state['verification'] = verification
    if exit_code == 0:
        state['state'] = 'verified'
        evidence = 'verificación configurada del proyecto pasó sobre el candidato entregado'
    elif exit_code is None:
        state['auto_verify'] = None  # que Jhon decida cómo verificar
        evidence = output + '; queda para Jhon'
    else:
        state['state'] = 'implementation_ready'
        evidence = 'verificación configurada falló; vuelve a Teo'
    state = save(db, identifier, AUTO_VERIFIER, session, 'auto-verify', state, evidence, time.time())
    db.commit()
    return state


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
        if action == 'status':
            state = read(db, identifier)
            require(state is not None, 'Unknown workflow')
            return with_next_step(state)
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
            fingerprint(root, files)
            supersedes = payload.get('supersedes')
            if supersedes:
                previous = read(db, supersedes)
                require(previous is not None and previous['state'] not in TERMINAL,
                        'supersedes debe nombrar un workflow abierto')
                previous['state'] = 'superseded'
                previous['superseded_by'] = identifier
                save(db, supersedes, actor, session, 'superseded', previous, f'reemplazado por {identifier}', now)
            risk = classification['risk']
            task = payload.get('task')
            require(task is None or (isinstance(task, str) and task.count('/') == 1), 'task debe ser "plan-slug/task-slug"')
            state = {'id': identifier, 'risk': risk, 'files': files, 'acceptance': payload['acceptance'],
                     'reuse': payload['reuse'], 'task': task, 'visual': classification['visual'],
                     'state': 'implementation_ready' if risk == 'low' else ('clarified' if risk == 'medium' else 'requested'),
                     'route': classification['route'], 'agents': classification['agents'],
                     'started_at': now, 'handoffs': 0, 'checks': [], 'oracle': None, 'digest': None,
                     'base_head': base_head(root), 'delivery_number': 0, 'delivery': None,
                     'verification_template': verification_template(root),
                     'verification_timeout': verification_timeout(root),
                     'auto_verify': auto_verification(root, files) if risk == 'low' else None,
                     # Comando de verificación que declara el proyecto, congelado
                     # acá: Jhon/Luz lo corren con check {configured: true} sin
                     # pedir permiso (en OpenCode v2 un plugin no puede pedirlo).
                     'configured_verification': auto_verification(root, files),
                     'supersedes': supersedes, 'start_session': session}
            record_start_metrics(db, identifier, classification, payload.get('intent'), supersedes)
        else:
            require(state is not None, 'Unknown workflow')
            require(state['state'] not in TERMINAL, f"{state['state']} workflows are immutable")
            if action in TRANSITIONS:
                owner, previous, target = TRANSITIONS[action]
                require(actor == owner and state['state'] == previous, f'{action} requires {owner} in {previous}')
                require(action == 'deliver' or bool(str(evidence).strip()), 'Transition evidence required')
                if action == 'ready':
                    require_approved_plan(db, payload.get('plan_id'))
                    state['plan_id'] = payload['plan_id']
                if action == 'deliver':
                    require_scope(root, state['files'])
                    state['digest'] = fingerprint(root, state['files'])
                    state['implementation_session'] = session
                    state['oracle'] = None
                    state['checks'] = []
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
                require(bool(str(evidence).strip()), 'Rescope requires evidence explaining the additional files')
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
                state['files'] = widened
                state['digest'] = None
                state['oracle'] = None
                state['checks'] = []
                state['verification'] = None
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
                    state['auto_verify'] = render_verification(template, widened) if risk == 'low' else None
                    state['state'] = 'implementation_ready'
            elif action == 'oracle':
                require(actor == 'jhon' and state['state'] == 'verification_ready', 'Only Jhon prepares the oracle before verification')
                require(session != state['implementation_session'], 'Independent verifier session required')
                fields = ('expected', 'negative', 'invariant', 'refutation')
                require(all(isinstance(payload.get(f), str) and payload[f].strip() for f in fields), 'Complete independent oracle required')
                require(state['oracle'] is None, 'Oracle is frozen for this delivery')
                state['oracle'] = {f: payload[f] for f in fields}
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
                relevant = [c for c in state['checks'] if c['agent'] == actor and c['digest'] == state['digest']]
                require(relevant, f'{actor} must record at least one check on the current candidate before approving')
                require(all(c['exit_code'] == 0 for c in relevant),
                        'A failing check is on record for this candidate; a later passing one does not erase it')
                if actor == 'luz':
                    state['quality_findings'] = payload['findings']
                state['state'] = target
            elif action == 'reject':
                require(actor in {'jhon', 'luz'} and state['state'] in {'verification_ready', 'verified', 'quality_reviewed'}, 'Invalid rejection')
                require(bool(str(evidence).strip()), 'Rejection requires diagnostic evidence')
                state['state'] = 'implementation_ready'
                state['oracle'] = None
                state['checks'] = []
            elif action == 'complete':
                require(actor == 'alex', 'Only Alex completes a workflow')
                expected = 'documented' if state['risk'] == 'high' else 'verified'
                require(state['state'] == expected, f'Completion requires {expected}')
                require_scope(root, state['files'])
                require_index_in_scope(root, state['files'])
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed after verification')
                state['state'] = 'completed'
                state['completed_at'] = now
                state['duration_ms'] = round((now - state['started_at']) * 1000)
                verifier = (state.get('verification') or {}).get('agent', 'jhon')
                state['receipt_tree_hash'] = seal_receipt(db, root, identifier, state['files'], verifier, state['digest'])
                state['usage'] = runtime_usage(state.get('start_session'), state['started_at'], now)
                record_finish_metrics(db, identifier, state['duration_ms'], state['handoffs'], state['usage'],
                                      max(0, state.get('delivery_number', 1) - 1))
            else:
                raise ValueError('Unknown workflow action')
        state = save(db, identifier, actor, session, action, state, evidence, now)
        db.commit()
        if action == 'deliver' and state['state'] == 'verification_ready' and state.get('auto_verify'):
            state = auto_verify(db, root, identifier, session)
        return with_next_step(state)
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


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, _cancel)
    signal.signal(signal.SIGINT, _cancel)
    try:
        print(json.dumps(operate(json.load(sys.stdin))))
    except (ValueError, KeyError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
