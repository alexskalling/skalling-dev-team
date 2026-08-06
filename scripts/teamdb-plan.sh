#!/usr/bin/env bash
# teamdb-plan.sh — Crea proposal+plan+tasks+DAG+history en una pasada
# T-2.17v2
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

usage() {
  cat <<EOF
Uso: teamdb-plan.sh <project> <slug> <title> <tasks.md>

Crea proposal+plan+tasks en una sola operación. Parsea tasks.md con formato:
  - [ ] Título de la task
  - [ ] Otra task _depends: [task-1, task-2]

Opcional:
  --by <actor>              actor (default: TEAMDB_ACTOR o 'sol')
  --purpose <text>          purpose por defecto aplicado a cada task (v0.7.7 Bloque 2)
  --acceptance <text>        acceptance_md por defecto aplicado a cada task
  --strict-contract         rechaza tasks sin purpose o acceptance_md no vacío

NO escribe en work_in_progress. Solo en las tablas cycle (proposals/plans/tasks).
EOF
  exit 2
}

if [ "$#" -lt 4 ]; then
  usage
fi

PROJECT="${1:?Falta project}"
SLUG="${2:?Falta slug}"
TITLE="${3:?Falta title}"
TASKS_MD="${4:?Falta tasks.md}"
shift 4

ACTOR=""
DEFAULT_PURPOSE=""
DEFAULT_ACCEPTANCE=""
STRICT_CONTRACT="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --by=*) ACTOR="${1#--by=}" ;;
    --by) shift; ACTOR="${1:-}" ;;
    --purpose=*) DEFAULT_PURPOSE="${1#--purpose=}" ;;
    --purpose) shift; DEFAULT_PURPOSE="${1:-}" ;;
    --acceptance=*) DEFAULT_ACCEPTANCE="${1#--acceptance=}" ;;
    --acceptance) shift; DEFAULT_ACCEPTANCE="${1:-}" ;;
    --strict-contract) STRICT_CONTRACT="1" ;;
    -*) echo "[ERROR] opción desconocida: $1" >&2; exit 2 ;;
    *) echo "[ERROR] argumento posicional no soportado: $1" >&2; exit 2 ;;
  esac
  shift || break
done

ACTOR="${ACTOR:-${TEAMDB_ACTOR:-sol}}"

# Bloque 2 v0.7.7: heurística título-poético. Solo activa en strict-contract.
# Rechaza títulos tipo "Gimme Shelter": 4+ palabras TODO lowercase separadas por espacios.
is_poetic_title() {
  local t="$1"
  # 4+ palabras lowercase (canciones tipo "gimme shelter now please"). Sin -i.
  if printf '%s' "$t" | grep -qE "^[a-záéíóúñü]+[[:space:]]+[a-záéíóúñü]+[[:space:]]+[a-záéíóúñü]+[[:space:]]+[a-záéíóúñü]+"; then
    return 0
  fi
  return 1
}

# Bloque 2 v0.7.7: aplicar heurística al título del plan también
if [ "$STRICT_CONTRACT" = "1" ] && is_poetic_title "$TITLE"; then
  echo "[ERROR] plan title parece poético: '$TITLE'. Usá título descriptivo." >&2
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }
[ -f "$TASKS_MD" ] || { echo "[ERROR] tasks.md no existe: $TASKS_MD" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 3. Parsear tasks.md a TSV temporal (no toca DB: el fallo de parse no deja parcial)
TMP_DIR="$(mktemp -d)"
TMP_TSV="$TMP_DIR/tasks.tsv"
: > "$TMP_TSV"
ORDER=0
while IFS= read -r line; do
  # Match - [ ] o - [x] o -[] (case patterns usan quoting)
  case "$line" in
    "- [ ] "*|"- [x] "*|"-[] "*)
      # Extraer titulo + deps con bash builtin (mas seguro que ${var#pat})
      if [[ "$line" == "- [ ] "* ]]; then
        raw="${line#"- [ ] "}"
      elif [[ "$line" == "- [x] "* ]]; then
        raw="${line#"- [x] "}"
      else
        raw="${line#"-[] "}"
      fi
      # Detectar _depends: [a, b]
      deps=""
      title="$raw"
      case "$raw" in
        *" _depends: ["*"]"*)
          deps_part="${raw##*_depends: \[}"
          deps_part="${deps_part%\]}"
          title="${raw% _depends: \[*\]}"
          deps="$(printf '%s' "$deps_part" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',' | sed 's/,$//')"
          ;;
      esac
      # Slug con prefijo task- para consistencia
      slug_part="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//;s/--*/-/g')"
      [ -z "$slug_part" ] && slug_part="$ORDER"
      task_slug="task-$slug_part"
      # Bloque 2 v0.7.7: rechazar títulos poéticos en strict-contract
      if [ "$STRICT_CONTRACT" = "1" ] && is_poetic_title "$title"; then
        echo "[ERROR] task '$task_slug' tiene título poético: '$title'. Usá título descriptivo (verbo + objeto)." >&2
        rm -rf "$TMP_DIR"
        exit 1
      fi
      printf '%s\t%s\t%s\t%s\n' "$ORDER" "$task_slug" "$title" "$deps" >> "$TMP_TSV"
      ORDER=$((ORDER + 1))
      ;;
  esac
done < "$TASKS_MD"

# 4-6. Atomicidad (Issue 7): proposal+plan+tasks+edges+history en UNA transaccion.
# Si cualquier INSERT falla (ej: trigger, constraint) → rollback → DB limpia.
# Idempotencia (Issue 9): si ya existe history 'created', no se inserta otro.
# Bloque 2 v0.7.7: enforcement de purpose + acceptance_md via --strict-contract.
# Pre-checks (título poético, purpose+AC) corren en bash ANTES de tocar la DB.
python3 - "$DB" "$SLUG" "$TITLE" "$ACTOR" "$NOW" "$TMP_TSV" "$DEFAULT_PURPOSE" "$DEFAULT_ACCEPTANCE" "$STRICT_CONTRACT" <<'PYEOF'
import sqlite3, sys
db, slug, title, actor, now, tsv_path, default_purpose, default_acceptance, strict_contract = sys.argv[1:10]
strict = (strict_contract == "1")
conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
try:
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(
        "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,'draft','pol',?,?) "
        "ON CONFLICT(slug) DO UPDATE SET updated_at=excluded.updated_at",
        (slug, title, "# Intent\n\n" + title, now, now))
    proposal_id = conn.execute("SELECT id FROM proposals WHERE slug = ?", (slug,)).fetchone()[0]
    intent_md = conn.execute("SELECT intent_md FROM proposals WHERE id = ?", (proposal_id,)).fetchone()[0] or ""
    conn.execute(
        "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_by,updated_by,version,created_at,updated_at) "
        "VALUES(?,?,?,?,?,?,?,?,?,?,?) "
        "ON CONFLICT(slug) DO UPDATE SET updated_at=excluded.updated_at, updated_by=excluded.updated_by",
        (slug, title, proposal_id, "# Design\n\nDefined by ADRs during execution.", "draft", "sol", actor, actor, 1, now, now))
    plan_id = conn.execute("SELECT id FROM plans WHERE slug = ?", (slug,)).fetchone()[0]
    # Backfill intent_md si quedó NULL en planes pre-migración
    conn.execute("UPDATE plans SET intent_md = ? WHERE id = ? AND (intent_md IS NULL OR intent_md = '')", (intent_md, plan_id))
    task_count = 0
    edge_count = 0
    with open(tsv_path) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            idx, tslug, ttitle, deps = line.split('\t', 3)
            purpose = default_purpose
            acceptance = default_acceptance
            if strict and not purpose:
                print("[ERROR] task '%s' requiere purpose (v0.7.7 strict-contract). Pasá --purpose=<text>." % tslug, file=sys.stderr)
                raise SystemExit(2)
            if strict and not acceptance:
                print("[ERROR] task '%s' requiere acceptance_md (v0.7.7 strict-contract). Pasá --acceptance=<text>." % tslug, file=sys.stderr)
                raise SystemExit(2)
            conn.execute(
                "INSERT OR IGNORE INTO tasks(plan_id,slug,title,description_md,acceptance_md,purpose,status,priority,order_index,owner,created_at,updated_at) "
                "VALUES(?,?,?,?,?,?,'pending',2,?,?,?,?)",
                (plan_id, tslug, ttitle, "", acceptance, purpose, idx, actor, now, now))
            task_count += 1
            if deps:
                for dep_slug in deps.split(','):
                    if not dep_slug:
                        continue
                    conn.execute(
                        "INSERT OR IGNORE INTO task_dependencies(task_id, depends_on_task_id, type, created_at) "
                        "SELECT t.id, d.id, 'blocks', ? FROM tasks t JOIN tasks d ON d.plan_id = t.plan_id AND d.slug = ? "
                        "WHERE t.plan_id = ? AND t.slug = ?",
                        (now, dep_slug, plan_id, tslug))
                    edge_count += 1
    created_exists = conn.execute(
        "SELECT COUNT(*) FROM plan_history WHERE plan_id = ? AND operation = 'created'",
        (plan_id,)).fetchone()[0]
    if created_exists == 0:
        new_version = conn.execute(
            "SELECT COALESCE(MAX(version), 0) + 1 FROM plan_history WHERE plan_id = ?",
            (plan_id,)).fetchone()[0]
        conn.execute(
            "INSERT INTO plan_history(plan_id,version,changed_by,changed_at,operation,diff_md) VALUES(?,?,?,?,'created',?)",
            (plan_id, new_version, actor, now, "Created with %d tasks, %d edges" % (task_count, edge_count)))
    else:
        new_version = conn.execute(
            "SELECT COALESCE(MAX(version), 0) FROM plan_history WHERE plan_id = ?",
            (plan_id,)).fetchone()[0]
    conn.commit()
    print("plan: %s (plan_id=%d, %d tasks, %d edges, history v%d)" % (slug, plan_id, task_count, edge_count, new_version))
except SystemExit as e:
    conn.rollback()
    sys.exit(e.code)
except Exception as e:
    conn.rollback()
    print("[ERROR] %s" % e, file=sys.stderr)
    sys.exit(1)
PYEOF
PLAN_RC=$?

rm -rf "$TMP_DIR"
exit $PLAN_RC
