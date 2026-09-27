"""Reglas únicas de clasificación de pedidos.

Las usan skalling-route.sh (vista previa, research/audit) y el motor
skalling_workflow (`start`, la única puerta para implementar código). Antes
cada uno tenía su propia copia de las reglas y divergían: por eso vive acá.

Contrato:
- scope cross-cutting o sensible  -> high
- scope module con riesgo low     -> medium
- decisión pendiente o ambigüedad -> needs_user_decision (no se implementa)
- visual NO sube el riesgo: un cambio visual trivial sigue siendo trivial;
  exige, eso sí, que exista el sistema de diseño en TeamDB.
"""
from contextlib import closing
import sqlite3
import subprocess
from pathlib import Path

ROUTES = {
    'low': ('FAST-TRACK', 'Alex → Teo (verificación automática; Jhon si no hay comando de verificación)', 'focused'),
    'medium': ('INLINE', 'Alex → Sol → Teo → Jhon', 'module'),
    'high': ('SDD', 'Alex → Pol → Sol → Teo → Jhon → Luz → Pau', 'full'),
}


def normalize(kind, risk, scope='unknown', clarity='clear', decision='none', sensitive=False, visual=False):
    if kind not in {'code', 'research', 'audit'}:
        raise ValueError('kind requerido: code, research o audit')
    if risk not in {'low', 'medium', 'high'}:
        raise ValueError('risk debe ser low, medium o high')
    if scope not in {'local', 'module', 'cross-cutting', 'unknown'}:
        raise ValueError('scope inválido')
    if clarity not in {'clear', 'ambiguous'}:
        raise ValueError('clarity inválida')
    if decision not in {'none', 'pending', 'resolved'}:
        raise ValueError('decision inválida')
    needs_user_decision = decision == 'pending' or clarity == 'ambiguous'
    if sensitive or scope == 'cross-cutting' or needs_user_decision:
        risk = 'high'
    elif scope == 'module' and risk == 'low':
        risk = 'medium'
    if kind == 'research':
        route, agents, verification = 'RESEARCH', 'Alex → Jes', 'sources'
    elif kind == 'audit':
        route, agents, verification = 'DIRECT', 'Alex → Luz', 'audit'
    elif scope == 'unknown':
        route, agents, verification = ROUTES['high']
    else:
        route, agents, verification = ROUTES[risk]
    return {
        'kind': kind, 'risk': risk, 'scope': scope, 'route': route, 'agents': agents,
        'verification': verification, 'visual': bool(visual),
        'needs_user_decision': needs_user_decision,
        'implementation_allowed': kind == 'code' and scope != 'unknown' and not needs_user_decision,
    }


def readiness(db_path):
    try:
        with closing(sqlite3.connect('file:' + str(db_path) + '?mode=ro', uri=True)) as db, db:
            row = db.execute("SELECT value FROM schema_meta WHERE key='project_readiness' LIMIT 1").fetchone()
    except sqlite3.Error:
        return 'missing'
    return (row[0] if row and row[0] else 'missing')


def memory_blockers(db_path, visual):
    """Lo mínimo que un implementador necesita leer antes de tocar código."""
    blockers = []
    try:
        with closing(sqlite3.connect('file:' + str(db_path) + '?mode=ro', uri=True)) as db, db:
            if not db.execute("SELECT 1 FROM concepts WHERE slug='project-summary' AND length(body_md)>0").fetchone():
                blockers.append('Falta resumen de proyecto en TeamDB')
            if visual and not db.execute("SELECT 1 FROM concepts WHERE slug='design-system' AND length(body_md)>0").fetchone():
                blockers.append('Falta sistema de diseño en TeamDB')
    except sqlite3.Error as error:
        blockers.append('TeamDB ilegible: ' + str(error))
    return blockers


def project_db(root):
    """TeamDB del proyecto: la del repositorio PRINCIPAL también desde un git
    worktree (la base está gitignored y solo existe en el checkout original).
    Misma regla que teamdb_project_path en lib-teamdb.sh; los archivos a
    verificar siguen siendo los del worktree."""
    root = Path(root)
    try:
        out = subprocess.run(['git', 'rev-parse', '--git-common-dir'], cwd=root, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        out = None
    if out is not None and out.returncode == 0 and out.stdout.strip():
        common = Path(out.stdout.strip())
        if not common.is_absolute():
            common = root / common
        return common.resolve().parent / '.opencode/context/team.db'
    return root / '.opencode/context/team.db'
