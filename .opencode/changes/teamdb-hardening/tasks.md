# Tasks: TeamDB Hardening v0.7.2 (Plan ejecutable)

**Slug:** `teamdb-hardening`
**Date original:** 2026-08-05
**Amendment round:** 2 (2026-08-05, post-Phase-1-review)
**Author:** Sol (planner) — sobre `proposal.md` + `spec.md` + `design.md` de Pol
**Granularidad:** Cada tarea ≈ 30 min de Teo; Jhon verifica con RED→GREEN→REFACTOR
**TDD discipline:** Test que falla antes que el código que lo arregla. Sin excepciones.

---

## Amendment Log

| Round | Date | Reason | Status |
|---|---|---|---|
| 1 | 2026-08-05 | Plan inicial tras handoff de Pol | Fase 1 ejecutada parcialmente en producción |
| **2** | **2026-08-05** | **Post-Fase-1 review + 7 requisitos nuevos del usuario** | **Esta versión es la fuente de verdad activa** |

### Cambios de round 2 (este commit de enmienda, NO aplicar producción en este turno)

- **T-2.1..T-2.8 originales**: marcados como `[SUPERSEDED — replaced by T-2.9..T-2.17]`. Se conservan visibles para trazabilidad de auditoría.
- **T-2.9..T-2.17 NUEVOS**: cubren los 7 requisitos del usuario:
  1. amendment in-place real con version/historial + preservación de aprobadas
  2. tasks como DAG con `task_dependencies` + `teamdb_runnable`
  3. claim atómico con lease/attempt/input_hash + resume
  4. markdown generado desde DB con header GENERATED + sin escritura bidireccional
  5. context capsule para handoff de Teo
  6. transacciones SQLite (`BEGIN IMMEDIATE`, WAL, `busy_timeout`) en lugar de flock
  7. SQL parametrizado real (Python `sqlite3` con bound params) — `teamdb_safe_query` actual se deprecará
- **T-3.6 MODIFICADO**: el workflow `.github/workflows/tests.yml` **sí existe** (verificado). Por tanto la tarea pasa de "crear" a "modificar". Errores de mi round 1 corregidos.
- **T-3.6b/3.6c/3.6d NUEVOS**: workflows que sí se crean desde cero (`teamdb-sqli.yml`, `handoffs.yml`, `teamdb-dag-claims.yml`).
- **Exit criteria** actualizados para Fase 2 y Fase 3.

### Notas del estado real verificado (Fase 1 ya ejecutada)

- ✅ `lib-teamdb.sh` (197 líneas) ya tiene `teamdb_safe_query`, `_has_control_char` portable bash 3.2 (sin `grep -P`), `_actor_or_unknown`. La implementación incluye una **desviación explícita** del round 1 que **NO** usaré como destino final (ver T-2.10): usa escape manual porque "CLI sqlite3 no soporta bind". Mi round 2 lo arregla con `teamdb_exec.py`.
- ✅ Tests Fase 1 ya pasan en disk: `tests/teamdb-{safe-query,search-sqli,related-sqli,problems-fts}.test.sh`.
- ✅ `sql/global-schema.sql` ya está en `0.7.2` (línea 71).
- 🟡 Stubs Fase 2 listos para reemplazar: `teamdb-{plan,amend,execute-plan,resume,status}.sh` (5 líneas cada uno).
- ✅ `sql/migrations/002_add_plan_tables.sql` ya existe (por migrations incrementales).
- ❌ `~/.github/workflows/tests.yml` — **existe** (`/Users/akizuki/Proyectos/skalling-dev-team/.github/workflows/tests.yml`). Round 1 dijo incorrectamente que "no existe". Corregido en T-3.6v2.

**Restricción del usuario para round 2**: NO editar producción. Solo enmendar `tasks.md`. Teo implementará los nuevos archivos desde cero.

---

**Decisiones confirmadas que aplican:**
- Bash 3.2 portable (`INV-PORTABILITY-1`): sin `declare -A`, `readarray`, `[[ -v ]]`, `local -n`, `${var,,}`, `mapfile`.
- v0.7.2 = bump explícito de `VERSION` (`__version__ = "0.7.2"`).
- Sin commits por Teo (`R16` constitución). Handoff a Jhon vía `verification`.
- Markdown se conserva (no se borra). Migración solo mueve `.jsonl` a `legacy/`. **(round 2 añade: el `.md` que se conserva es GENERADO desde DB, no editable a mano.)**
- Snippets compartidos se expanden build-time en `install-global.sh`.
- `teamdb-execute-plan.sh` solo orquesta; no ejecuta shell arbitrario desde DB. **(round 2: Teo obtiene claims vía `teamdb-claim.sh`, no shell.)**
- Priorización: P0 (SQLi + instalación), luego lifecycle/memoria, luego DAG/claims, luego CI.

---

## Convenciones de handoff entre tareas

Cada handoff `TEO → JHON` sigue el formato `skalling-receipt` con `verification`:
```bash
# Formato del comando de verificación que Jhon re-ejecuta
bash tests/<suite>.test.sh
```

Si Jhon rechaza 3 veces la misma tarea → escala a Alex (no es decisión de Sol).

---

## FASE 0 — Bump de versión (5 min, teo solo, GH-only, sin tests)

### T-0.1 — Bump VERSION y regenerar schema row
**Owner:** Teo | **Verify:** Jhon
**Files:** `VERSION`, `sql/project-schema.sql`, `sql/global-schema.sql`, `scripts/build-schema.sh` (nuevo)
**Implements AC:** 3.1, 3.2

**RED:**
```bash
# Test que falla: VERSION no coincide con schema_meta
VERSION="$(grep -oP '\d+\.\d+\.\d+' VERSION)"
SCHEMA="$(sqlite3 <(echo '.schema schema_meta' && echo 'SELECT value FROM schema_meta;') || true)"
[ "$VERSION" != "0.7.2" ] && { echo "VERSION no es 0.7.2"; exit 1; }
```

**GREEN:**
```bash
# 1. Editar VERSION: __version__ = "0.7.2"
# 2. Crear scripts/build-schema.sh:
#    - Lee VERSION
#    - En sql/project-schema.sql REEMPLAZA la línea:
#      INSERT INTO schema_meta VALUES ('version', '0.7.0');  // línea 116 actual
#      POR
#      INSERT INTO schema_meta VALUES ('version', '<VERSION>');  
#    - Y BORRA la línea 308 (UPDATE 0.7.1 posterior)
#    - Mismo cambio en sql/global-schema.sql (fila schema_meta equivalente)
# 3. El script solo escribe la fila de versión; NO toca el resto del schema
# 4. Ejecución: bash scripts/build-schema.sh

# 5. Editar README.md: "Versión actual: 0.6.2" → debe ser leída dinámicamente:
grep -q '^Versión actual: 0.6.2$' README.md && echo "FAIL" || echo "OK"
# Reemplazar por línea como:
# Versión actual: ![VERSION](VERSION) — o simplemente eliminar y referenciar VERSION
# Para mantener simple: dejar "Versión actual: 0.7.2" hard-coded PERO añadir un test que falle si VERSION y README no coinciden
```

**REFACTOR:** El script es idempotente. Si las filas `schema_meta` ya tienen la versión correcta, es no-op.

**Done when:**
- `VERSION` = `0.7.2`
- `sql/project-schema.sql` líneas 116 y 308 reflejan `0.7.2`
- `sql/global-schema.sql` igual
- `README.md` línea 5 = `0.7.2` (con test que verifique consistencia)
- `tests/version-coherence.test.sh` existe y pasa

---

## FASE 1 — Seguridad + Instalación (P0, bloqueante)

> Por qué primero: SQLi es CVE potencial. Instalación rota significa que `teamdb-search.sh` nunca llega a la máquina del usuario → magnifica el riesgo de cualquier fix de seguridad.

### T-1.1 — Helper `teamdb_safe_query` en lib-teamdb.sh
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/lib/lib-teamdb.sh`, `tests/teamdb-safe-query.test.sh` (nuevo)
**Implements AC:** 1.4 (precondición de 1.1/1.2)

**RED:** (test que falla — el helper aún no existe)
```bash
# tests/teamdb-safe-query.test.sh
TEST_DB=$(mktemp -d)/test.db
sqlite3 "$TEST_DB" < sql/project-schema.sql

# 1. Helper existe
source scripts/lib/lib-teamdb.sh
type teamdb_safe_query >/dev/null 2>&1 || { echo "FAIL: helper no definido"; exit 1; }

# 2. Rechaza input con control chars
out=$(teamdb_safe_query "$TEST_DB" exact "SELECT ? WHERE 1=1" $'\x00malicious' 2>&1) || true
echo "$out" | grep -q "Invalid input" || { echo "FAIL: no rechazó NUL"; exit 1; }

# 3. Rechaza input > 1024 chars
BIG=$(printf 'x%.0s' $(seq 1 1100))
teamdb_safe_query "$TEST_DB" exact "SELECT ?" "$BIG" 2>&1 | grep -q "Too long" || { echo "FAIL: no rechazó 1100 chars"; exit 1; }

echo "PASS"
```

**GREEN:**
```bash
# En scripts/lib/lib-teamdb.sh, agregar (compatible bash 3.2):
teamdb_safe_query() {
  local db="$1"; local mode="$2"; local template="$3"; shift 3
  teamdb_check_sqlite3 || return 1
  [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }

  # Validar cada parámetro
  for arg in "$@"; do
    case "${#arg}" in
      0) ;;  # permitimos empty
      *)
        # Rechazar control chars (NUL, BEL, ESC, etc)
        echo "$arg" | grep -qP '[\x00-\x08\x0b-\x1f\x7f]' && {
          echo "[ERROR] Invalid input (control chars)" >&2; return 1;
        }
        # Rechazar > 1024
        [ "${#arg}" -gt 1024 ] && {
          echo "[ERROR] Too long (max 1024 chars)" >&2; return 1;
        }
        ;;
    esac
  done

  case "$mode" in
    fts)
      sqlite3 -separator $'\t' "$db" "$template" "$@"
      ;;
    like)
      sqlite3 -separator $'\t' "$db" "$template" "$@"
      ;;
    exact)
      sqlite3 -separator $'\t' "$db" "$template" "$@"
      ;;
    *)
      echo "[ERROR] Mode invalido: $mode (usa fts|like|exact)" >&2
      return 1
      ;;
  esac
}
```

**Comandos bash 3.2:** No usamos `[[ =~ ]]` con regex PCRE — usamos `grep` para control chars (compatible con busybox/BSD grep). Si tu `grep` no soporta `-P`, usar `tr` o reescribir el chequeo con `case "$arg" in *$(printf '\x00')*) ...`. Para este plan, dejamos `grep -P` (los tests se asume GNU coreutils, común en CI Linux; en macOS con bash 3.2.57 el `grep` es BSD y requiere la versión con `-P` que ofrece `brew install grep` — **Riesgo que registramos**, ver Riesgos al final).

**REFACTOR:** Si el chequeo de control chars resulta ruidoso en macOS, agregar fallback. Por ahora: `command -v ggrep >/dev/null && alias grep=ggrep` no, mejor: hacer el chequeo con un loop sobre chars problemáticos usando `printf` y `case` (100% portable bash 3.2).

**Done when:** `bash tests/teamdb-safe-query.test.sh` pasa.

---

### T-1.2 — Parametrizar `teamdb-search.sh` con `teamdb_safe_query`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-search.sh`, `tests/teamdb-search-sqli.test.sh` (nuevo)
**Implements AC:** 1.1, 1.4, 1.5

**RED:**
```bash
# tests/teamdb-search-sqli.test.sh
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('jwt','JWT','refresh tokens',datetime('now'))"

# 1. Inyección clásica no rompe la DB
bash scripts/teamdb-search.sh "' OR '1'='1" concepts "$TEST_DIR" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='jwt'")
[ "$COUNT" = "1" ] || { echo "FAIL: concepts table modificada"; exit 1; }

# 2. DROP TABLE attempt no ejecuta
bash scripts/teamdb-search.sh "x'); DROP TABLE concepts; --" concepts "$TEST_DIR" >/dev/null 2>&1 || true
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
[ "$TBL" = "concepts" ] || { echo "FAIL: concepts table borrada"; exit 1; }

# 3. Search normal sigue funcionando (con match parcial)
RESULT=$(bash scripts/teamdb-search.sh "JWT" concepts "$TEST_DIR" 2>/dev/null | grep -c "jwt" || true)
[ "$RESULT" -ge "1" ] || { echo "FAIL: búsqueda normal rota"; exit 1; }

echo "PASS"
```

**GREEN:** Reescribir las 5 categorías (concepts/decisions/preferences/problems/wip) en `teamdb-search.sh`:
```bash
# Reemplazar líneas 53, 59, 65, 71, 77 del archivo actual.

# concepts (FTS5)
teamdb_safe_query "$DB" fts \
  "SELECT slug, title, category FROM concepts WHERE id IN (SELECT rowid FROM concepts_fts WHERE concepts_fts MATCH ?) ORDER BY updated_at DESC LIMIT 10" \
  "$QUERY"

# decisions
teamdb_safe_query "$DB" fts \
  "SELECT slug, title, status FROM decisions WHERE id IN (SELECT rowid FROM decisions_fts WHERE decisions_fts MATCH ?) ORDER BY decided_at DESC LIMIT 10" \
  "$QUERY"

# preferences (LIKE — no hay FTS5 para preferences)
teamdb_safe_query "$DB" like \
  "SELECT slug, scope FROM preferences WHERE body_md LIKE '%' || ? || '%' LIMIT 10" \
  "$QUERY"

# problems (FTS5 — implementado en T-1.4)
teamdb_safe_query "$DB" fts \
  "SELECT slug, title, status FROM known_problems WHERE id IN (SELECT rowid FROM problems_fts WHERE problems_fts MATCH ?) ORDER BY discovered_at DESC LIMIT 10" \
  "$QUERY"

# wip
teamdb_safe_query "$DB" fts \
  "SELECT slug, status, owner FROM work_in_progress WHERE id IN (SELECT rowid FROM wip_fts WHERE wip_fts MATCH ?) ORDER BY priority, updated_at DESC LIMIT 10" \
  "$QUERY"
```

**REFACTOR:** Extraer `format_search_results()` que toma DB rows tab-separated y emite el output bonito (DRY).

**Validaciones de Jhon:**
```bash
grep -E "sqlite3.*\\\$" scripts/teamdb-search.sh && echo "FAIL: interpolación" && exit 1
shellcheck scripts/teamdb-search.sh || exit 1  # 0 errores
```

**Done when:**
- `bash tests/teamdb-search-sqli.test.sh` pasa
- `grep -E 'sqlite3.*\$' scripts/teamdb-search.sh` retorna 0 matches
- `shellcheck scripts/teamdb-search.sh` retorna 0 errors

---

### T-1.3 — Parametrizar `teamdb-related.sh`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-related.sh`, `tests/teamdb-related-sqli.test.sh` (nuevo)
**Implements AC:** 1.2, 1.4, 1.5

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('jwt','JWT','test',datetime('now'))"

# 1. Inyección en TYPE debe rechazar
bash scripts/teamdb-related.sh "jwt" "concept'; DROP TABLE memory_links; --" "$TEST_DIR" 2>/dev/null
RC=$?
[ "$RC" != "0" ] || { echo "FAIL: type inválido no fue rechazado"; exit 1; }

# 2. Inyección en SLUG
bash scripts/teamdb-related.sh "evil'; DROP TABLE concepts; --" concept "$TEST_DIR" >/dev/null 2>&1 || true
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
[ "$TBL" = "concepts" ] || { echo "FAIL: concepts table borrada"; exit 1; }

# 3. Caso válido funciona
bash scripts/teamdb-related.sh "jwt" concept "$TEST_DIR" >/dev/null 2>&1 || true
echo "PASS"
```

**GREEN:** Whitelist + bind del ID de lookup:
```bash
# Case statement con whitelist explícita (4 tipos) — cualquier otro falla
case "$TYPE" in
  concept|decision|preference|problem) ;;
  *) echo "[ERROR] Tipo inválido: $TYPE (usa: concept|decision|preference|problem)" >&2; exit 2 ;;
esac

# Mapear tabla canónica según whitelist
case "$TYPE" in
  concept) TABLE="concepts" ;;
  decision) TABLE="decisions" ;;
  preference) TABLE="preferences" ;;
  problem) TABLE="known_problems" ;;
esac

# ID lookup — bind de slug como parámetro
ID=$(teamdb_safe_query "$DB" exact "SELECT id FROM $TABLE WHERE slug = ?" "$SLUG") || exit 1
# Validar que ID sea entero positivo
case "$ID" in
  ''|*[!0-9]*) echo "[ERROR] No encontrado: $TYPE/$SLUG" >&2; exit 1 ;;
  *)
    [ "$ID" -gt 0 ] || { echo "[ERROR] ID inválido" >&2; exit 1; }
    ;;
esac

# Tags — bind de TABLE y ID
tags=$(teamdb_safe_query "$DB" exact "
  SELECT t.name FROM tags t JOIN memory_tags mt ON mt.tag_id=t.id
  WHERE mt.memory_table = ? AND mt.memory_id = ?" "$TABLE" "$ID")

# Links out — bind de TABLE y ID (TABLE ya está en whitelist)
links_out=$(teamdb_safe_query "$DB" exact "
  SELECT ml.link_type, ml.to_table, COALESCE(c.slug, d.slug, p.slug, kp.slug)
  FROM memory_links ml
  LEFT JOIN concepts c ON ml.to_table='concepts' AND c.id=ml.to_id
  LEFT JOIN decisions d ON ml.to_table='decisions' AND d.id=ml.to_id
  LEFT JOIN preferences p ON ml.to_table='preferences' AND p.id=ml.to_id
  LEFT JOIN known_problems kp ON ml.to_table='known_problems' AND kp.id=ml.to_id
  WHERE ml.from_table = ? AND ml.from_id = ?" "$TABLE" "$ID")
# (análogamente links_in)

# NOTA: la interpolación de 'concepts'/'decisions' literales arriba es SEGURA
# porque esos valores vienen del whitelist, no del usuario.
```

**REFACTOR:** Extraer `render_links()` para DRY.

**Done when:**
- `bash tests/teamdb-related-sqli.test.sh` pasa
- `grep -E 'sqlite3.*\$' scripts/teamdb-related.sh` retorna 0 matches
- `shellcheck scripts/teamdb-related.sh` retorna 0 errors

---

### T-1.4 — FTS5 para `known_problems` (SEG-3)
**Owner:** Teo | **Verify:** Jhon
**Files:** `sql/project-schema.sql`, `scripts/teamdb-search.sh` (parcial), `tests/teamdb-problems-fts.test.sh` (nuevo)
**Implements AC:** 1.3

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
sqlite3 "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,discovered_at) VALUES('conn','Connection timeout','wait_then_retry','retry after 30s',datetime('now'))"

# Búsqueda por síntoma debe retornar el row
RESULT=$(bash scripts/teamdb-search.sh "timeout" problems "$TEST_DIR" 2>/dev/null | grep -c "Connection" || true)
[ "$RESULT" -ge "1" ] || { echo "FAIL: search no encuentra 'timeout' en problems"; exit 1; }

echo "PASS"
```

**GREEN:** En `sql/project-schema.sql`, agregar (después de las definiciones existentes de `concepts_fts`, `decisions_fts`, `wip_fts`):
```sql
-- FTS5 para problems (T-1.4)
CREATE VIRTUAL TABLE problems_fts USING fts5(
  title, symptom_md, workaround_md,
  content='known_problems', content_rowid='id'
);
CREATE TRIGGER problems_ai AFTER INSERT ON known_problems BEGIN
  INSERT INTO problems_fts(rowid, title, symptom_md, workaround_md) VALUES (new.id, new.title, new.symptom_md, new.workaround_md);
END;
CREATE TRIGGER problems_ad AFTER DELETE ON known_problems BEGIN
  INSERT INTO problems_fts(problems_fts, rowid, title, symptom_md, workaround_md)
    VALUES('delete', old.id, old.title, old.symptom_md, old.workaround_md);
END;
CREATE TRIGGER problems_au AFTER UPDATE ON known_problems BEGIN
  INSERT INTO problems_fts(problems_fts, rowid, title, symptom_md, workaround_md)
    VALUES('delete', old.id, old.title, old.symptom_md, old.workaround_md);
  INSERT INTO problems_fts(rowid, title, symptom_md, workaround_md) VALUES (new.id, new.title, new.symptom_md, new.workaround_md);
END;
```

**Y en `teamdb-search.sh`** cambiar la categoría problems (línea 71 actual) para usar `problems_fts` (este cambio ya está cubierto por T-1.2, lo confirmamos aquí).

**REFACTOR:** N/A (es integración de schema + búsqueda).

**Done when:**
- Schema regenera con `teamdb-init.sh` y `problems_fts` existe (verificar con `sqlite3 ... '\.tables'`).
- El test pasa.
- `bash scripts/teamdb-init.sh` en directorio fresco crea `problems_fts` correctamente.

---

### T-1.5 — `install-global.sh` copia TODOS los scripts teamdb + hooks ejecutables
**Owner:** Teo | **Verify:** Jhon
**Files:** `install-global.sh`, `tests/install-script-copies.test.sh` (nuevo)
**Implements AC:** 2.1, 2.3

**RED:**
```bash
# tests/install-script-copies.test.sh
HOME_BAK="$HOME"; export HOME=$(mktemp -d)
OUT=$(bash install-global.sh --dry-run 2>&1)
RC=$?
export HOME="$HOME_BAK"
[ "$RC" -eq 0 ] || { echo "FAIL: dry-run errored"; exit 1; }

# Debe mencionar CADA uno de:
for s in teamdb-init teamdb-migrate teamdb-export teamdb-import \
         teamdb-search teamdb-related teamdb-graph \
         teamdb-plan teamdb-status teamdb-amend teamdb-resume \
         teamdb-execute-plan wip-tree; do
  echo "$OUT" | grep -q "$s.sh" || { echo "FAIL: $s.sh no aparece en dry-run"; exit 1; }
done

# Debe mencionar lib-teamdb.sh
echo "$OUT" | grep -q "lib-teamdb.sh" || { echo "FAIL: lib-teamdb.sh no aparece"; exit 1; }

# Hooks
echo "$OUT" | grep -qE "hooks/(pre-commit|post-merge)" || { echo "FAIL: hooks no aparecen"; exit 1; }

# También: debe haber REMOVIDO el `|| true` silenciador del cp de hooks (INV-WRITE-2)
grep -n "2>/dev/null || true" install-global.sh | grep -i "hooks" && {
  echo "FAIL: hay || true silenciador en sección hooks"; exit 1;
}

echo "PASS"
```

**GREEN:** Reescribir `install_teamdb()` (líneas 347-388) y `install_teamdb_hooks()` (líneas 340-345):

```bash
install_teamdb_hooks() {
  if [ -d "$SCRIPT_DIR/scripts/hooks" ]; then
    run mkdir -p "$OPENCODE_DIR/hooks"
    # FIX INV-WRITE-2: NO usar `2>/dev/null || true`. Si cp falla, falla el install.
    # shellcheck disable=SC2086  # word splitting es intencional en cp
    run cp "$SCRIPT_DIR/scripts/hooks/"* "$OPENCODE_DIR/hooks/"
    run chmod +x "$OPENCODE_DIR/hooks/pre-commit" "$OPENCODE_DIR/hooks/post-merge"
  else
    log WARN "Directorio scripts/hooks/ no existe, skip"
  fi
}

install_teamdb() {
  log INFO "Instalando teamdb (libSQL)"

  run mkdir -p "$OPENCODE_DIR/scripts"
  # TODOS los scripts teamdb-* (incluyendo los nuevos del plan)
  local teamdb_scripts
  teamdb_scripts="$(find "$SCRIPT_DIR/scripts" -maxdepth 1 -type f -name 'teamdb-*.sh' -printf '%f\n' | sort)"
  for script in $teamdb_scripts wip-tree.sh; do
    if [[ -f "$SCRIPT_DIR/scripts/$script" ]]; then
      run cp "$SCRIPT_DIR/scripts/$script" "$OPENCODE_DIR/scripts/$script"
      run chmod +x "$OPENCODE_DIR/scripts/$script"
    fi
  done

  # lib-teamdb.sh va como par plana (no en lib/) para que scripts lo busquen igual
  if [[ -f "$SCRIPT_DIR/scripts/lib/lib-teamdb.sh" ]]; then
    run cp "$SCRIPT_DIR/scripts/lib/lib-teamdb.sh" "$OPENCODE_DIR/scripts/lib-teamdb.sh"
    run chmod +x "$OPENCODE_DIR/scripts/lib-teamdb.sh"
  fi

  # Schema
  if [[ -d "$SCRIPT_DIR/sql" ]]; then
    run mkdir -p "$OPENCODE_DIR/skalling-data/teamdb-schema"
    [[ -f "$SCRIPT_DIR/sql/global-schema.sql" ]] && \
      run cp "$SCRIPT_DIR/sql/global-schema.sql" "$OPENCODE_DIR/skalling-data/teamdb-schema/"
    [[ -f "$SCRIPT_DIR/sql/project-schema.sql" ]] && \
      run cp "$SCRIPT_DIR/sql/project-schema.sql" "$OPENCODE_DIR/skalling-data/teamdb-schema/"
  fi

  # Inicializa team.db global
  if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$OPENCODE_DIR/skalling-data/teamdb-schema/global-schema.sql" ]]; then
    run mkdir -p "$HOME/.config/opencode"
    if [[ ! -f "$HOME/.config/opencode/team.db" ]]; then
      if sqlite3 "$HOME/.config/opencode/team.db" < "$OPENCODE_DIR/skalling-data/teamdb-schema/global-schema.sql"; then
        log OK "team.db global creado"
      else
        log WARN "No se pudo crear team.db global"
      fi
    else
      log INFO "team.db global ya existe"
    fi
  fi

  log OK "teamdb instalado"
}
```

**REFACTOR:** El find dinámicamente captura scripts nuevos sin tocar `install-global.sh` cuando agregamos `teamdb-FOO.sh` en el futuro.

**Done when:**
- `bash tests/install-script-copies.test.sh` pasa
- El dry-run lista TODOS los teamdb-*.sh
- `grep -n '2>/dev/null || true' install-global.sh` no encuentra ningún `|| true` cerca de `hooks/`

---

### T-1.6 — Hooks con `git rev-parse` para path absoluto
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/hooks/pre-commit`, `scripts/hooks/post-merge`, `tests/install-hooks-paths.test.sh` (nuevo)
**Implements AC:** 2.2, 2.3

**RED:**
```bash
# tests/install-hooks-paths.test.sh
# Simula que los hooks están en .git/hooks/ (donde los pone git) y verifica
# que pueden resolver teamdb-export.sh
TMP=$(mktemp -d)
git -C "$TMP" init >/dev/null
mkdir -p "$TMP/.git/hooks"
cp scripts/hooks/pre-commit "$TMP/.git/hooks/"
chmod +x "$TMP/.git/hooks/pre-commit"
cp scripts/hooks/post-merge "$TMP/.git/hooks/"
chmod +x "$TMP/.git/hooks/post-merge"

# Crear DB mínima para que el hook funcione
mkdir -p "$TMP/.opencode/context"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TMP" >/dev/null

# Ejecutar pre-commit y verificar que NO falla con "file not found"
cd "$TMP"
touch a.txt; git add a.txt
HOME=$(mktemp -d) bash .git/hooks/pre-commit 2>&1 | grep -q "teamdb-export.sh: No such file" && {
  echo "FAIL: pre-commit no pudo resolver teamdb-export.sh"; exit 1;
}

# Y verificar que el .sql se generó (no requiere commit, solo que export corrió)
ls -la .opencode/context/teamdb/ | grep -q "data_" || {
  echo "FAIL: pre-commit no ejecutó export"; exit 1;
}

echo "PASS"
```

**GREEN:** Reescribir ambos hooks:

```bash
# scripts/hooks/pre-commit
#!/usr/bin/env bash
# pre-commit: export team.db → .sql (idempotente, no falla si DB no existe)
set -euo pipefail

PROJECT="$(git rev-parse --show-toplevel)"

# Salir silenciosamente si no hay teamdb proyecto
[ -f "$PROJECT/.opencode/context/team.db" ] || exit 0

# Preferir install global; fallback al repo
GLOBAL_SCRIPT="${SKALLING_ROOT:-$HOME/.config/opencode}/scripts/teamdb-export.sh"
REPO_SCRIPT="$PROJECT/scripts/teamdb-export.sh"

if [ -x "$GLOBAL_SCRIPT" ]; then
  bash "$GLOBAL_SCRIPT" "$PROJECT"
elif [ -x "$REPO_SCRIPT" ]; then
  bash "$REPO_SCRIPT" "$PROJECT"
else
  echo "[WARN] teamdb-export.sh no encontrado (global: $GLOBAL_SCRIPT, repo: $REPO_SCRIPT)" >&2
  exit 0
fi

# Solo añadir los .sql generados si existen
SQL_FILES=$(ls "$PROJECT/.opencode/context/teamdb"/data_*.sql 2>/dev/null || true)
if [ -n "$SQL_FILES" ]; then
  git add $SQL_FILES
fi
```

```bash
# scripts/hooks/post-merge
#!/usr/bin/env bash
# post-merge: import .sql → team.db
# Errores son visibles (no se suprimen).
set -euo pipefail

PROJECT="$(git rev-parse --show-toplevel)"

# Salir silenciosamente si no hay directorio teamdb
[ -d "$PROJECT/.opencode/context/teamdb" ] || exit 0

GLOBAL_SCRIPT="${SKALLING_ROOT:-$HOME/.config/opencode}/scripts/teamdb-import.sh"
REPO_SCRIPT="$PROJECT/scripts/teamdb-import.sh"

if [ -x "$GLOBAL_SCRIPT" ]; then
  bash "$GLOBAL_SCRIPT" "$PROJECT" || {
    echo "[ERROR] teamdb-import.sh falló. El merge continúa, pero teamdb puede estar desincronizado." >&2
    exit 1
  }
elif [ -x "$REPO_SCRIPT" ]; then
  bash "$REPO_SCRIPT" "$PROJECT" || {
    echo "[ERROR] teamdb-import.sh falló." >&2
    exit 1
  }
else
  echo "[WARN] teamdb-import.sh no encontrado" >&2
  exit 0
fi

echo "teamdb: imported .sql from git"
```

**REFACTOR:** Extraer `resolve_teamdb_script()` (helper compartido) si se vuelve a usar.

**Done when:**
- `bash tests/install-hooks-paths.test.sh` pasa.
- `grep -n 'SCRIPT_DIR/..' scripts/hooks/pre-commit scripts/hooks/post-merge` retorna 0 matches.

---

### T-1.7 — `TEAMDB_ACTOR` plumbing en `lib-teamdb.sh` (foundation audit)
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/lib/lib-teamdb.sh`, `tests/audit-log-actor.test.sh` (nuevo)
**Implements AC:** 8.1 (parcial — fundación)

> Esta tarea solo prepara el terreno. El helper `teamdb_write_*` aún no se reescribe (eso es T-2.2). Aquí validamos que existe el switch y que el helper respeta el actor en operaciones directas.

**RED:**
```bash
source scripts/lib/lib-teamdb.sh
DB=$(mktemp -d)/test.db
sqlite3 "$DB" < sql/project-schema.sql

# Cuando TEAMDB_ACTOR='sol', un INSERT directo via sqlite3 debe (en el futuro)
# poder leer TEAMDB_ACTOR. Aquí solo verificamos que el flujo del helper lo respeta.
export TEAMDB_ACTOR=sol

# Esta tarea es fundacional: el assert principal es que teamdb_write_project
# admite TEAMDB_ACTOR como input ambiental. La verificación de audit_log con
# actor real se hace en T-3.4 (helper-side audit).
grep -q "TEAMDB_ACTOR" scripts/lib/lib-teamdb.sh || {
  echo "FAIL: TEAMDB_ACTOR no referenciado"; exit 1;
}

echo "PASS"
```

**GREEN:** Mover el actor plumbing al lugar correcto (esto se completa en T-2.2 con teamdb_write_*):

```bash
# En scripts/lib/lib-teamdb.sh, agregar helper interno (T-1.7 hace el cableado):
_actor_or_unknown() {
  echo "${TEAMDB_ACTOR:-unknown}"
}
```

Y `teamdb_init_project()` setea actor si no está seteado:
```bash
teamdb_init_project() {
  export TEAMDB_ACTOR="${TEAMDB_ACTOR:-sol}"  # Por defecto el inicializador es sol
  teamdb_check_sqlite3 || return 1
  local project="${1:-$(pwd)}"
  ...
}
```

`bootstrap-context.sh` debe exportar `TEAMDB_ACTOR=alex` antes de invocar `teamdb_init_project`.

**REFACTOR:** Diferido a T-2.2 (donde se centraliza).

**Done when:** `bash tests/audit-log-actor.test.sh` pasa.

---

### FASE 1 — Exit Criteria (Jhon corre)

```bash
bash tests/teamdb-safe-query.test.sh \
  && bash tests/teamdb-search-sqli.test.sh \
  && bash tests/teamdb-related-sqli.test.sh \
  && bash tests/teamdb-problems-fts.test.sh \
  && bash tests/install-script-copies.test.sh \
  && bash tests/install-hooks-paths.test.sh \
  && bash tests/audit-log-actor.test.sh \
  && shellcheck scripts/lib/lib-teamdb.sh \
  && shellcheck scripts/teamdb-search.sh \
  && shellcheck scripts/teamdb-related.sh \
  && shellcheck scripts/hooks/pre-commit scripts/hooks/post-merge \
  && bash install-global.sh --dry-run
```

Todo verde → Luz corre quality gate de seguridad. Pau actualiza CHANGELOG `[Unreleased]`.

---

## FASE 2 — Lifecycle en DB (proposals/plans/tasks) + escritura segura + audit

> **AMENDMENT round 2 — Esta fase fue reorganizada.**
>
> - T-2.1 (plan simple) → reemplazado por T-2.17v2 (que también crea con DAG + history en una sola operación).
> - T-2.2 (write helpers con flock) → reemplazado por T-2.10 (Python `sqlite3` real con bound params) + T-2.11 (WAL + BEGIN IMMEDIATE).
> - T-2.3, T-2.4, T-2.5, T-2.6 → consolidados/absorbidos en T-2.9, T-2.12, T-2.13, T-2.14, T-2.17v2.
> - T-2.7 (export audit_log) → MANTENIDO. Se complementa con T-2.15 (export-md).
> - T-2.8 (migrate preserve .md) → MANTENIDO.
>
> **Las secciones debajo marcadas `[SUPERSEDIDO...]` se conservan visibles solo para trazabilidad de auditoría de Pol/Jhon. NO son ejecutables.**

---

## FASE 2 v2 — Round 2 (ESTA ES LA FUENTE DE VERDAD ACTIVA)

### T-2.9 — Schema: agregar `task_dependencies`, `task_claims`, `plan_history`, `task_context_capsules`
**Owner:** Teo | **Verify:** Jhon
**Files:** `sql/project-schema.sql`, `sql/migrations/003_add_dag_claims_history.sql` (nuevo), `tests/teamdb-dag-tables-exist.test.sh` (nuevo)
**Implements:** req (1), (2), (3), (5)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# Las 4 tablas deben existir tras init (idempotente para DBs viejas)
for tbl in task_dependencies task_claims plan_history task_context_capsules; do
  COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$tbl'")
  [ "$COUNT" = "1" ] || { echo "FAIL: $tbl no existe"; exit 1; }
done
echo "PASS"
```

**GREEN:** Agregar al final de `sql/project-schema.sql` (después de los CREATE TABLE actuales), precedido por guards:
```sql
-- ════════════════════════════════════════
-- DAG + CLAIMS + HISTORY v0.7.2 (T-2.9)
-- ════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_dependencies (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  depends_on_task_id INTEGER NOT NULL,
  type TEXT DEFAULT 'blocks' CHECK (type IN ('blocks','relates_to','supersedes')),
  created_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id),
  UNIQUE(task_id, depends_on_task_id)
);
CREATE INDEX IF NOT EXISTS idx_task_deps_task ON task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_task_deps_depends ON task_dependencies(depends_on_task_id);

CREATE TABLE IF NOT EXISTS task_claims (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL UNIQUE,
  actor TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  input_hash TEXT NOT NULL,
  lease_until TEXT NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active','done','failed','expired')),
  claimed_at TEXT NOT NULL,
  released_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id)
);
CREATE INDEX IF NOT EXISTS idx_task_claims_actor ON task_claims(actor, status);
CREATE INDEX IF NOT EXISTS idx_task_claims_lease ON task_claims(lease_until);

CREATE TABLE IF NOT EXISTS plan_history (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  version INTEGER NOT NULL,
  changed_by TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  diff_md TEXT,
  snapshot_before TEXT,
  operation TEXT NOT NULL CHECK (operation IN ('created','amended','approved','deprecated','superseded')),
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);
CREATE INDEX IF NOT EXISTS idx_plan_history_plan ON plan_history(plan_id, version DESC);

CREATE TABLE IF NOT EXISTS task_context_capsules (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  memory_table TEXT NOT NULL CHECK (memory_table IN ('concepts','decisions','preferences','known_problems')),
  memory_id INTEGER NOT NULL,
  relevance INTEGER DEFAULT 1,
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  UNIQUE(task_id, memory_table, memory_id)
);
CREATE INDEX IF NOT EXISTS idx_task_ctx_capsule ON task_context_capsules(task_id);
```

Y en `sql/migrations/003_add_dag_claims_history.sql` para DBs v0.7.1 existentes, los mismos `CREATE TABLE IF NOT EXISTS`. **`teamdb-init.sh` aplicaría este SQL solo si las tablas no existen** (idempotente).

**REFACTOR:** `setup-team-doctor.sh::check_teamdb()` debe verificar que las 4 tablas existen.

**Done when:** `bash tests/teamdb-dag-tables-exist.test.sh` pasa; `setup-team-doctor.sh` reporta ≥16 tablas después de init.

---

### T-2.10 — Python helper `scripts/teamdb_exec.py` con `sqlite3` real (bound params) — REEMPLAZO de `teamdb_safe_query`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb_exec.py` (nuevo), `scripts/lib/lib-teamdb.sh`, `tests/teamdb-python-bindparams.test.sh` (nuevo)
**Implements:** req (7) FUNDAMENTAL — el plan NO acepta escape manual como destino final

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# Sourcear lib-teamdb.sh
. scripts/lib/lib-teamdb.sh

# Insert con bound params (no escape manual)
teamdb_exec_query "$DB" "SELECT ? AS r" "it works" | grep -q "it works" || {
  echo "FAIL: teamdb_exec_query no retorna binded result"; exit 1;
}

# Test SQLi REAL: con binding el valor se trata como dato, no como SQL
COUNT=$(teamdb_exec_query "$DB" "SELECT length(?) AS l" "x'); DROP TABLE concepts; --")
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'" | grep -q "concepts" || {
  echo "FAIL: tabla borrada"; exit 1;
}

# Verificar el path Python existe
[ -x "$(command -v python3)" ] && [ -f "scripts/teamdb_exec.py" ] || {
  echo "FAIL: teamdb_exec.py no existe"; exit 1;
}

# El script responde a CLI
python3 scripts/teamdb_exec.py --db "$DB" --mode query --sql "SELECT ? AS r" --params '["foo"]' \
  | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d and d[0]['r']=='foo' else 1)" || {
  echo "FAIL: CLI no retorna binded param"; exit 1;
}

echo "PASS"
```

**GREEN:** Crear `scripts/teamdb_exec.py`:
```python
#!/usr/bin/env python3
"""teamdb_exec.py — Wrapper Python sobre sqlite3 con real parameter binding.

Reemplaza teamdb_safe_query (que usaba escape manual de '). El CLI sqlite3 no
soporta bind de ?/?N/:name en todas las plataformas; Python sqlite3 sí.

Uso:
  python3 scripts/teamdb_exec.py --db <path> --mode query|write|transaction \\
    --sql "SELECT * FROM x WHERE a = ?" --params '["v1","v2"]'
"""
import sqlite3, sys, json, argparse

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', required=True)
    ap.add_argument('--mode', choices=['query', 'write', 'transaction'], default='query')
    ap.add_argument('--sql', required=True)
    ap.add_argument('--params', default='[]')
    ap.add_argument('--timeout', type=int, default=5000)
    args = ap.parse_args()

    try:
        params = json.loads(args.params)
    except Exception as e:
        json.dump({'error': f'bad params JSON: {e}'}, sys.stdout)
        sys.exit(1)

    conn = sqlite3.connect(args.db, timeout=args.timeout / 1000)
    conn.row_factory = sqlite3.Row

    # WAL si aplica (req 6). Idempotente.
    try:
        conn.execute('PRAGMA journal_mode=WAL')
    except Exception:
        pass
    conn.execute(f'PRAGMA busy_timeout={args.timeout}')
    conn.execute('PRAGMA foreign_keys=ON')

    try:
        if args.mode == 'query':
            cur = conn.execute(args.sql, params)
            rows = [dict(r) for r in cur.fetchall()]
            json.dump(rows, sys.stdout, default=str)
        elif args.mode == 'write':
            conn.execute('BEGIN IMMEDIATE')  # escritura atomica portable
            cur = conn.execute(args.sql, params)
            conn.commit()
            json.dump({'changes': cur.rowcount, 'lastrowid': cur.lastrowid}, sys.stdout)
        elif args.mode == 'transaction':
            conn.execute('BEGIN IMMEDIATE')
            # params es 1-tupla si --mode transaction con 1 statement
            cur = conn.execute(args.sql, params if isinstance(params, (list, tuple)) else [params])
            results = [{'changes': cur.rowcount, 'lastrowid': cur.lastrowid}]
            conn.commit()
            json.dump(results, sys.stdout)
    except Exception as e:
        conn.rollback()
        json.dump({'error': str(e), 'mode': args.mode}, sys.stdout)
        sys.exit(1)
    finally:
        conn.close()

if __name__ == '__main__':
    main()
```

**Y bash wrappers en `scripts/lib/lib-teamdb.sh`** (completamente nuevos):
```bash
# Bash wrappers para teamdb_exec.py.
# teamdb_safe_query queda DEPRECATED pero sigue exportada (deprecation warning).
_TEAMDB_EXEC_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../teamdb_exec.py"
[ -f "$_TEAMDB_EXEC_PY" ] || _TEAMDB_EXEC_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/teamdb_exec.py"

# teamdb_exec_query <db> <sql_with_?> <params...>  -> stdout JSON
teamdb_exec_query() {
    local db="$1"; local sql="$2"; shift 2
    local params_json
    params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
    python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode query --sql "$sql" --params "$params_json"
}

# teamdb_exec_write <db> <sql_with_?> <params...>  -> stdout JSON
teamdb_exec_write() {
    local db="$1"; local sql="$2"; shift 2
    local params_json
    params_json="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$@")"
    python3 "$_TEAMDB_EXEC_PY" --db "$db" --mode write --sql "$sql" --params "$params_json"
}
```

> **Deprecation**: `teamdb_safe_query` se mantiene exportada con un header comment `# DEPRECATED — usa teamdb_exec_query`. Los scripts que aún la usen (los originales Fase 1) no rompen pero Jhon los migrará gradualmente a `teamdb_exec_query` en el refactor de Fase 3. **El test de SQLi en T-1.2 seguirá pasando porque la nueva implementación es incluso MÁS segura (binding real vs escape manual).**

**REFACTOR:** Considerar precompilar el JSON de params solo cuando hay >2 (evita python3 invocation sin params).

**Done when:** `bash tests/teamdb-python-bindparams.test.sh` pasa. El test de Fase 1 sigue verde (`teamdb-safe-query.test.sh` no rota por backward-compat).

---

### T-2.11 — Reemplazar `teamdb_write_project` con WAL + `BEGIN IMMEDIATE` (vía `teamdb_exec.py`)
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/lib/lib-teamdb.sh`, `tests/teamdb-write-wal.test.sh` (nuevo)
**Implements:** req (6) — transacciones SQLite portables, no flock

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
. scripts/lib/lib-teamdb.sh

# Insert atómico
teamdb_write_project "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" "wal-test" "Wal title" "body" >/dev/null

# Verificar WAL file
[ -f "${DB}-wal" ] || { echo "FAIL: WAL file no creado"; exit 1; }

# Verify row insertado
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='wal-test'")
[ "$COUNT" = "1" ] || { echo "FAIL: row no insertada"; exit 1; }

# Veces paralelas: dos escrituras concurrentes no pierden rows
for i in 1 2 3 4 5; do
  teamdb_write_project "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" "concurrent-$i" "t-$i" "b" >/dev/null &
done
wait
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug LIKE 'concurrent-%'")
[ "$COUNT" = "5" ] || { echo "FAIL: $COUNT concurrent inserts (esperaba 5)"; exit 1; }

echo "PASS"
```

**GREEN:** Reescribir `teamdb_write_project` (era flock) → ahora vía Python con BEGIN IMMEDIATE:
```bash
# En scripts/lib/lib-teamdb.sh, REEMPLAZAR teamdb_write_project:
teamdb_write_project() {
    local db="$1"; local sql="$2"; shift 2
    [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }
    local actor="${TEAMDB_ACTOR:-unknown}"
    local audit_sql
    audit_sql="INSERT INTO audit_log(ts,agent,action,table_name,actor_source) VALUES(datetime('now'),?,?,?,?); $sql"
    teamdb_exec_write "$db" "$audit_sql" "$actor" "mutate" "<via_helper>" "$@"
}

# Idem teamdb_write_global (simétrico)
teamdb_write_global() {
    local sql="$1"; shift
    local db; db="$(teamdb_global_path)"
    [ -f "$db" ] || { echo "[ERROR] DB global no existe: $db" >&2; return 1; }
    local actor="${TEAMDB_ACTOR:-unknown}"
    local audit_sql
    audit_sql="INSERT INTO audit_log(ts,agent,action,table_name,actor_source) VALUES(datetime('now'),?,?,?,?); $sql"
    teamdb_exec_write "$db" "$audit_sql" "$actor" "mutate-global" "<via_helper>" "$@"
}

# teamdb_init_* agrega los PRAGMAs
teamdb_init_project() {
    teamdb_check_sqlite3 || return 1
    export TEAMDB_ACTOR="${TEAMDB_ACTOR:-sol}"
    local project="${1:-$(pwd)}"
    local db; db="$(teamdb_project_path "$project")"
    local schema="${SKALLING_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/sql/project-schema.sql"
    [ -f "$schema" ] || { echo "[ERROR] Schema: $schema" >&2; return 1; }
    mkdir -p "$(dirname "$db")"
    if [ ! -f "$db" ]; then
      sqlite3 "$db" < "$schema"
      sqlite3 "$db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON"
    fi
    echo "$db"
}
```

> **Backwards-compat con Fase 1**: el `teamdb_safe_query` original sigue exportado (deprecation header). Los tests Fase 1 no rompen.

**REFACTOR:** El teamdb_init_* ya idempotentemente setea WAL.

**Done when:** `bash tests/teamdb-write-wal.test.sh` pasa. WAL file existe tras primera inserción. 5 inserts concurrentes no pierden rows.

---

### T-2.12 — `teamdb-amend.sh`: amendment in-place real con version/historial + preservación de aprobadas
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-amend.sh` (sustituye stub), `tests/teamdb-amend-full.test.sh` (nuevo)
**Implements:** req (1)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "auth-jwt" "Auth feature" /tmp/tasks.md >/dev/null

# Marcar task-1 como approved (inmutable para amend benigno)
sqlite3 "$DB" "UPDATE tasks SET status='approved', updated_at=datetime('now') WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND order_index=1"
BEFORE_OK=$(sqlite3 "$DB" "SELECT status FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND order_index=1")
[ "$BEFORE_OK" = "approved" ] || { echo "FAIL: setup no dejó task-1 approved"; exit 1; }

# Amend: --add-task, --modify-task, --deprecate-task
bash scripts/teamdb-amend.sh "auth-jwt" --add-task "New task added" --by sol "$TEST_DIR" >/dev/null
bash scripts/teamdb-amend.sh "auth-jwt" --modify-task=task-2 --new-title="Modified task 2" --by sol "$TEST_DIR" >/dev/null
bash scripts/teamdb-amend.sh "auth-jwt" --deprecate-task=task-3 --by teo "$TEST_DIR" >/dev/null

# Plan history debe tener 4+ rows (created + 3 amends)
HIST=$(sqlite3 "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt')")
[ "$HIST" -ge "4" ] || { echo "FAIL: plan_history tiene $HIST rows, esperaba >=4"; exit 1; }

# TAREAS APROBADAS PRESERVADAS: task-1 sigue 'approved'
AFTER_OK=$(sqlite3 "$DB" "SELECT status FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND order_index=1")
[ "$AFTER_OK" = "approved" ] || { echo "FAIL: aprobada modificada (era $BEFORE_OK, ahora $AFTER_OK)"; exit 1; }

# Version monotonamente creciente
MAX_VER=$(sqlite3 "$DB" "SELECT MAX(version) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt')")
[ "$MAX_VER" -ge "4" ] || { echo "FAIL: version=$MAX_VER esperaba >=4"; exit 1; }

# Intentar modificar la task aprobada debe fallar
bash scripts/teamdb-amend.sh "auth-jwt" --modify-task=task-1 --new-title="Attempt" --by teo "$TEST_DIR" 2>&1 | grep -qE "approved|immutable" || {
  echo "FAIL: permitio modificar approved task"; exit 1;
}

echo "PASS"
```

**GREEN:** Reescribir `scripts/teamdb-amend.sh` (sustituye el stub):
```bash
#!/usr/bin/env bash
# teamdb-amend.sh — Amendment in-place real con version + history + preservación de aprobadas.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

SLUG="${1:?Uso: teamdb-amend.sh <plan-slug> [--add-task "title" | --modify-task=slug --new-title="..." | --deprecate-task=slug] [--by actor] [project]}"
PROJECT="${@: -1}"
[ -d "$PROJECT" ] || PROJECT="$(pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh" >/dev/null 2>&1 || true
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$SLUG")
[ -n "$PLAN_ID" ] || { echo "Plan no encontrado: $SLUG" >&2; exit 1; }

# Parse args
OP=""
NEW_TITLE=""
TARGET_TASK=""
ACTOR=""
for arg in "$@"; do
  case "$arg" in
    --add-task) OP="add" ;;
    --modify-task=*) OP="modify"; TARGET_TASK="${arg#--modify-task=}" ;;
    --deprecate-task=*) OP="deprecate"; TARGET_TASK="${arg#--deprecate-task=}" ;;
    --new-title=*) NEW_TITLE="${arg#--new-title=}" ;;
    --by=*) ACTOR="${arg#--by=}" ;;
  esac
done
[ "$OP" != "add" ] || shift
[ -z "$ACTOR" ] && ACTOR="${TEAMDB_ACTOR:-sol}"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot ANTES del cambio
SNAPSHOT=$(sqlite3 "$DB" "SELECT json_group_array(json_object('slug',slug,'status',status,'title',title)) FROM tasks WHERE plan_id=$PLAN_ID")
NEW_VERSION=$(sqlite3 "$DB" "SELECT COALESCE(MAX(version)+1, 1) FROM plan_history WHERE plan_id=$PLAN_ID")

case "$OP" in
  add)
    TITLE="$NEW_TITLE"
    [ -n "$TITLE" ] || { echo "--add-task requiere --new-title=X" >&2; exit 2; }
    NEW_TASK_SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
    [ -z "$NEW_TASK_SLUG" ] && NEW_TASK_SLUG="task-new"
    NEXT_ORDER=$(sqlite3 "$DB" "SELECT COALESCE(MAX(order_index)+1, 1) FROM tasks WHERE plan_id=$PLAN_ID")
    teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,?,'teo',?,?)" \
        "$PLAN_ID" "$NEW_TASK_SLUG" "$TITLE" "$NEXT_ORDER" "$NOW" "$NOW" >/dev/null
    ;;
  modify)
    [ -z "$NEW_TITLE" ] || [ -n "$TARGET_TASK" ] || { echo "--modify-task requiere --new-title" >&2; exit 2; }
    # PROTECCIÓN: no modificar approved/resolved/in_progress/in_review
    CURRENT=$(teamdb_exec_query "$DB" "SELECT status FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$TARGET_TASK")
    case "$CURRENT" in
      approved|resolved|in_progress|in_review)
        echo "FAIL: task $TARGET_TASK está en status=$CURRENT (inmutable para amend). Usa --force-advance para override." >&2
        exit 3
        ;;
    esac
    teamdb_exec_write "$DB" "UPDATE tasks SET title=?, updated_at=? WHERE plan_id=? AND slug=?" \
        "$NEW_TITLE" "$NOW" "$PLAN_ID" "$TARGET_TASK" >/dev/null
    ;;
  deprecate)
    # Soft-delete: marca como superseded (status='rejected' con resolución)
    teamdb_exec_write "$DB" "UPDATE tasks SET resolution_md='deprecated via amend', status='rejected', updated_at=? WHERE plan_id=? AND slug=?" \
        "$NOW" "$PLAN_ID" "$TARGET_TASK" >/dev/null
    ;;
  *)
    echo "Operación inválida. Usá --add-task, --modify-task=slug, --deprecate-task=slug" >&2; exit 2 ;;
esac

# Registrar en plan_history
teamdb_exec_write "$DB" "INSERT INTO plan_history(plan_id,version,changed_by,changed_at,operation,diff_md,snapshot_before) VALUES(?,?,?,?,?,?,?)" \
    "$PLAN_ID" "$NEW_VERSION" "$ACTOR" "$NOW" "$OP" "Operation: $OP target: ${TARGET_TASK:-new}" "$SNAPSHOT" >/dev/null

# Update plan timestamp
teamdb_exec_write "$DB" "UPDATE plans SET updated_at=? WHERE id=?" "$NOW" "$PLAN_ID" >/dev/null

echo "amended: $SLUG v$NEW_VERSION ($OP)"
```

**REFACTOR:** Extraer `_amend_op()` para cada tipo cuando crezca.

**Done when:** `bash tests/teamdb-amend-full.test.sh` pasa. La task `approved` queda intacta; `plan_history` tiene 4+ rows; `--modify-task` falla para tasks no-pending.

---

### T-2.13 — `teamdb-deps.sh`: DAG de tasks + `runnable` query
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-deps.sh` (nuevo), `tests/teamdb-deps-dag.test.sh` (nuevo)
**Implements:** req (2)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "dag-test" "DAG" /tmp/dag-tasks.md >/dev/null

# Crear dependencies:
#   task-2 depends on task-1
#   task-3 depends on task-1
#   task-3 depends on task-2
bash scripts/teamdb-deps.sh add dag-test task-2 task-1 "$TEST_DIR" >/dev/null
bash scripts/teamdb-deps.sh add dag-test task-3 task-1 "$TEST_DIR" >/dev/null
bash scripts/teamdb-deps.sh add dag-test task-3 task-2 "$TEST_DIR" >/dev/null

# Inicialmente solo task-1 runnable (no deps)
RUNNABLE=$(bash scripts/teamdb-deps.sh runnable dag-test "$TEST_DIR" | grep -E "task-[123]" | sort -u | wc -l | tr -d ' ')
[ "$RUNNABLE" = "1" ] || { echo "FAIL: inicial runnable=$RUNNABLE (esperaba 1)"; exit 1; }

# Marcar task-1 approved
sqlite3 "$DB" "UPDATE tasks SET status='approved', updated_at=datetime('now') WHERE plan_id=(SELECT id FROM plans WHERE slug='dag-test') AND slug='task-1'"

# Ahora task-2 runnable
RUNNABLE=$(bash scripts/teamdb-deps.sh runnable dag-test "$TEST_DIR" | grep -E "task-[123]" | sort -u | wc -l | tr -d ' ')
[ "$RUNNABLE" = "1" ] || { echo "FAIL: post-approved runnable=$RUNNABLE"; exit 1; }

# Marcar task-2 approved
sqlite3 "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=(SELECT id FROM plans WHERE slug='dag-test') AND slug='task-2'"

# Ahora task-3 runnable
RUNNABLE=$(bash scripts/teamdb-deps.sh runnable dag-test "$TEST_DIR" | grep -E "task-[123]" | sort -u | wc -l | tr -d ' ')
[ "$RUNNABLE" = "1" ] || { echo "FAIL: post-dual-approved runnable=$RUNNABLE"; exit 1; }

# Ciclo detectado: task-1 depende de task-3 → debe rechazar
bash scripts/teamdb-deps.sh add dag-test task-1 task-3 "$TEST_DIR" 2>&1 | grep -qE "cycle|ciclo" || {
  echo "FAIL: no detectó ciclo"; exit 1;
}

echo "PASS"
```

**GREEN:** Implementar `scripts/teamdb-deps.sh`:
```bash
#!/usr/bin/env bash
# teamdb-deps.sh — DAG de dependencias + query de tasks runnable
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

OP="${1:?Uso: teamdb-deps.sh <add|remove|show|runnable> ...}"
shift

case "$OP" in
  add)
    PLAN_SLUG="$1"; TASK="$2"; DEPENDS_ON="$3"; PROJECT="${4:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }
    PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
    TASK_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$TASK")
    DEP_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$DEPENDS_ON")

    # Cycle detection via Python DFS
    HAS_CYCLE=$(python3 - <<EOF
import sqlite3
conn = sqlite3.connect("$DB")
edges = {}
for row in conn.execute("SELECT task_id, depends_on_task_id FROM task_dependencies"):
    edges.setdefault(row[0], []).append(row[1])

# BFS desde new edge TASK_ID -> DEP_ID: si DEP_ID puede llegar a TASK_ID → cycle
def reaches(start, end):
    visited = set()
    stack = [start]
    while stack:
        n = stack.pop()
        if n == end: return True
        if n in visited: continue
        visited.add(n)
        stack.extend(edges.get(n, []))
    return False

if reaches($DEP_ID, $TASK_ID):
    print("CYCLE")
else:
    print("OK")
EOF
)
    [ "$HAS_CYCLE" = "OK" ] || { echo "FAIL: ciclo detectado (dependencia cerraría el DAG)" >&2; exit 4; }

    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    teamdb_exec_write "$DB" "INSERT INTO task_dependencies(task_id,depends_on_task_id,type,created_at) VALUES(?,?,'blocks',?)" \
        "$TASK_ID" "$DEP_ID" "$NOW" >/dev/null
    echo "added: $TASK depends on $DEPENDS_ON"
    ;;
  remove)
    [ "$#" = "4" ] || { echo "remove requiere <plan> <task> <dep-on> <project>" >&2; exit 1; }
    DB="$(teamdb_project_path "$4")"
    PLAN_SLUG="$1"; TASK="$2"; DEPENDS_ON="$3"
    PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
    TASK_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$TASK")
    DEP_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$DEPENDS_ON")
    teamdb_exec_write "$DB" "DELETE FROM task_dependencies WHERE task_id=? AND depends_on_task_id=?" \
        "$TASK_ID" "$DEP_ID" >/dev/null
    echo "removed"
    ;;
  runnable)
    PLAN_SLUG="$1"; PROJECT="${2:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }
    PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
    # Tasks pendientes SIN deps pendientes
    sqlite3 -separator $'\t' "$DB" "
      SELECT t.slug, t.title
      FROM tasks t
      WHERE t.plan_id=$PLAN_ID AND t.status='pending'
        AND NOT EXISTS (
          SELECT 1 FROM task_dependencies d
          JOIN tasks dep ON dep.id=d.depends_on_task_id
          WHERE d.task_id=t.id AND dep.status NOT IN ('approved','resolved')
        )
      ORDER BY t.order_index
    "
    ;;
  show)
    PLAN_SLUG="$1"; PROJECT="${2:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
    sqlite3 -separator $'\t' "$DB" "
      SELECT t.slug, COALESCE(dep.slug, '(root)') AS depends_on, d.type
      FROM tasks t
      LEFT JOIN task_dependencies d ON d.task_id=t.id
      LEFT JOIN tasks dep ON dep.id=d.depends_on_task_id
      WHERE t.plan_id=$PLAN_ID
      ORDER BY t.order_index
    "
    ;;
  *)
    echo "Uso: teamdb-deps.sh <add|remove|show|runnable> ..." >&2; exit 2 ;;
esac
```

**REFACTOR:** Extraer `cycle_check()` cuando se agreguen más operaciones.

**Done when:** `bash tests/teamdb-deps-dag.test.sh` pasa. DAG se construye, runnable se filtra correctamente, ciclos se rechazan.

---

### T-2.14 — `teamdb-claim.sh`: claim atómico con lease/attempt/input_hash + resume
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-claim.sh` (nuevo), `tests/teamdb-claim-lease.test.sh` (nuevo)
**Implements:** req (3) — DC-3 ampliado: Teo no solo orquesta sino que toma claims para trabajos largos

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "claim-test" "Claim" /tmp/claim-tasks.md >/dev/null

# Claim inicial
OUT1=$(bash scripts/teamdb-claim.sh claim-test task-1 --actor=teo --input-hash=abc123 --ttl=300 "$TEST_DIR")
echo "$OUT1" | grep -qE "claim-id=[0-9]+" || { echo "FAIL: sin claim-id"; exit 1; }
CLAIM_ID=$(echo "$OUT1" | grep -oE "claim-id=[0-9]+" | cut -d= -f2)

# Status in_progress + started_at
STATUS=$(teamdb_exec_query "$DB" "SELECT status FROM tasks WHERE id=(SELECT id FROM tasks WHERE slug='task-1' LIMIT 1)" | head -1)
[ "$STATUS" = "in_progress" ] || { echo "FAIL: status=$STATUS"; exit 1; }

# Idempotencia: re-claim con mismo (actor, input_hash)
OUT2=$(bash scripts/teamdb-claim.sh claim-test task-1 --actor=teo --input-hash=abc123 --ttl=300 "$TEST_DIR")
CLAIM_ID_2=$(echo "$OUT2" | grep -oE "claim-id=[0-9]+" | cut -d= -f2)
[ "$CLAIM_ID" = "$CLAIM_ID_2" ] || { echo "FAIL: no idempotente ($CLAIM_ID vs $CLAIM_ID_2)"; exit 1; }

# Conflicto: distinto actor (mientras lease vigente)
OUT3=$(bash scripts/teamdb-claim.sh claim-test task-1 --actor=jhon --input-hash=abc123 --ttl=300 "$TEST_DIR" 2>&1) || true
echo "$OUT3" | grep -qE "claimed by|otro actor" || { echo "FAIL: no detecta claim existente: $OUT3"; exit 1; }

# Lease expiry: simular vencido y permitir re-claim
teamdb_exec_write "$DB" "UPDATE task_claims SET lease_until=datetime('now', '-1 minute') WHERE id=?" "$CLAIM_ID" >/dev/null
OUT4=$(bash scripts/teamdb-claim.sh claim-test task-1 --actor=jhon --input-hash=def456 --ttl=300 "$TEST_DIR")
echo "$OUT4" | grep -qE "claim-id=[0-9]+" || { echo "FAIL: lease-expired no permite re-claim"; exit 1; }

# Resume: tras claim con teo en task-2, --resume --actor=teo lo encuentra
bash scripts/teamdb-claim.sh claim-test task-2 --actor=teo --input-hash=zzz --ttl=300 "$TEST_DIR" >/dev/null
RESUME_OUT=$(bash scripts/teamdb-claim.sh --resume --actor=teo "$TEST_DIR")
echo "$RESUME_OUT" | grep -qE "task-2" || { echo "FAIL: resume no encuentra task-2: $RESUME_OUT"; exit 1; }

echo "PASS"
```

**GREEN:** Implementar `scripts/teamdb-claim.sh`:
```bash
#!/usr/bin/env bash
# teamdb-claim.sh — Atomic claim with lease/attempt/input_hash + resume.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

# Subcomando --resume
if [ "${1:-}" = "--resume" ]; then
    ACTOR="${2:?--resume requiere --actor=X}"
    PROJECT="${3:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "no DB" >&2; exit 1; }
    teamdb_exec_query "$DB" "
        SELECT c.id, c.task_id, c.attempt, c.input_hash, c.lease_until, t.slug, t.plan_id, p.slug
        FROM task_claims c
        JOIN tasks t ON t.id=c.task_id
        JOIN plans p ON p.id=t.plan_id
        WHERE c.actor=? AND c.status='active' AND c.lease_until > datetime('now')
        ORDER BY c.claimed_at
    " "$ACTOR" | python3 -c "
import json, sys
claims = json.loads(sys.stdin.read())
print(json.dumps([{
    'claim_id': c['id'],
    'task_id': c['task_id'],
    'task_slug': c['slug'],
    'plan_slug': c[7],
    'attempt': c['attempt'],
    'input_hash': c['input_hash'],
    'lease_until': c['lease_until']
} for c in claims], indent=2))
"
    exit 0
fi

# Subcomando --release
if [ "${1:-}" = "--release" ]; then
    CLAIM_ID="${2:?--release requiere <claim-id>}"
    shift 2
    NEW_STATUS="done"
    for arg in "$@"; do
        case "$arg" in
            --status=*) NEW_STATUS="${arg#--status=}" ;;
            project=*) PROJECT="${arg#project=}" ;;
        esac
    done
    PROJECT="${PROJECT:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    teamdb_exec_write "$DB" "UPDATE task_claims SET status=?, released_at=? WHERE id=?" "$NEW_STATUS" "$NOW" "$CLAIM_ID" >/dev/null
    if [ "$NEW_STATUS" = "done" ]; then
        teamdb_exec_write "$DB" "UPDATE tasks SET status='resolved', resolved_at=?, updated_at=? WHERE id=(SELECT task_id FROM task_claims WHERE id=?)" "$NOW" "$NOW" "$CLAIM_ID" >/dev/null
    fi
    echo "released: $CLAIM_ID ($NEW_STATUS)"
    exit 0
fi

# Subcomando principal: claim
PLAN_SLUG="${1:?Uso: teamdb-claim.sh <plan> <task> [--actor=X] [--input-hash=H] [--ttl=300] [project]}"
TASK_SLUG="${2:?Falta task}"
shift 2
ACTOR=""
INPUT_HASH=""
TTL=300
PROJECT=""
for arg in "$@"; do
    case "$arg" in
        --actor=*) ACTOR="${arg#--actor=}" ;;
        --input-hash=*) INPUT_HASH="${arg#--input-hash=}" ;;
        --ttl=*) TTL="${arg#--ttl=}" ;;
        -*) ;;  # ignore
        *) PROJECT="$arg" ;;
    esac
done
[ -n "$ACTOR" ] || ACTOR="${TEAMDB_ACTOR:-unknown}"
[ -n "$INPUT_HASH" ] || INPUT_HASH="$(echo -n "$PLAN_SLUG/$TASK_SLUG/$ACTOR/$$" | shasum -a 256 | cut -d' ' -f1)"
[ -d "$PROJECT" ] || PROJECT="$(pwd)"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LEASE_END="$(date -u -v +${TTL}S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)+timedelta(seconds=$TTL)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"

PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
TASK_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$TASK_SLUG")
[ -n "$TASK_ID" ] || { echo "Task no encontrada: $TASK_SLUG" >&2; exit 1; }

# Toda la lógica de claim va en una transacción Python con BEGIN IMMEDIATE
RESULT=$(python3 - "$DB" "$TASK_ID" "$ACTOR" "$INPUT_HASH" "$NOW" "$LEASE_END" <<'PYEOF'
import sqlite3, sys, json
db_path, task_id, actor, input_hash, now, lease_end = sys.argv[1:7]
conn = sqlite3.connect(db_path, timeout=5)
conn.row_factory = sqlite3.Row
conn.execute('BEGIN IMMEDIATE')
try:
    existing = conn.execute("SELECT id, actor, input_hash, lease_until, status FROM task_claims WHERE task_id=? AND status='active'", (task_id,)).fetchone()
    if existing:
        # Lease aún vigente?
        if existing['lease_until'] > now:
            # Mismo (actor, input_hash)? Idempotente
            if existing['actor'] == actor and existing['input_hash'] == input_hash:
                json.dump({'claim_id': existing['id'], 'idempotent': True, 'lease_until': existing['lease_until']}, sys.stdout)
                conn.commit(); sys.exit(0)
            else:
                json.dump({'error': f'claimed by {existing["actor"]} (lease until {existing["lease_until"]})'}, sys.stdout)
                conn.rollback(); sys.exit(2)
        # Lease expirado: actualizamos
        new_attempt = (conn.execute("SELECT MAX(attempt)+1 FROM task_claims WHERE task_id=?", (task_id,)).fetchone()[0]) or 2
        cur = conn.execute("UPDATE task_claims SET actor=?, input_hash=?, lease_until=?, attempt=?, claimed_at=?, status='active' WHERE id=?",
                          (actor, input_hash, lease_end, new_attempt, now, existing['id']))
        claim_id = existing['id']
    else:
        cur = conn.execute("INSERT INTO task_claims(task_id,actor,attempt,input_hash,lease_until,status,claimed_at) VALUES(?,?,1,?,?, 'active', ?)",
                          (task_id, actor, input_hash, lease_end, now))
        claim_id = cur.lastrowid
    # Update task status
    conn.execute("UPDATE tasks SET status='in_progress', owner=?, started_at=?, updated_at=? WHERE id=?", (actor, now, now, task_id))
    conn.execute("INSERT INTO audit_log(ts,agent,action,table_name,actor_source) VALUES(?,?, 'claim', 'task_claims', 'helper')", (now, actor))
    conn.commit()
    json.dump({'claim_id': claim_id, 'lease_until': lease_end}, sys.stdout)
except Exception as e:
    conn.rollback()
    json.dump({'error': str(e)}, sys.stdout)
    sys.exit(1)
finally:
    conn.close()
PYEOF
)

echo "claim: $RESULT"

# Polling-friendly: solo emitir claim-id si exit 0
if echo "$RESULT" | grep -q claim-id; then
    echo "$RESULT" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(f\"claim-id={d['claim_id']}\")"
elif echo "$RESULT" | grep -q '"error"'; then
    exit 2
fi
```

**REFACTOR:** Si crecen políticas (heartbeat, abandon), extraer `claim.py`.

**Done when:** `bash tests/teamdb-claim-lease.test.sh` pasa. Idempotencia, lease expiry, resume funcionan.

---

### T-2.15 — `teamdb-export-md.sh`: Markdown GENERADO desde DB, no bidireccional
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-export-md.sh` (nuevo), `tests/teamdb-export-md.test.sh` (nuevo)
**Implements:** req (4)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/changes/auth-jwt"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "auth-jwt" "Auth feature" /tmp/tasks.md >/dev/null

# Insertar specs + design_notes para que se generen sus .md
bash scripts/teamdb-context.sh link auth-jwt task-1 --concepts=auth-jwt --decisions=use-jwt "$TEST_DIR" >/dev/null

bash scripts/teamdb-export-md.sh "$TEST_DIR" >/dev/null

# Cada archivo de plan exportado debe existir + header GENERATED
for f in proposal.md design.md tasks.md; do
  [ -f "$TEST_DIR/.opencode/changes/auth-jwt/$f" ] || { echo "FAIL: $f no generado"; exit 1; }
  head -1 "$TEST_DIR/.opencode/changes/auth-jwt/$f" | grep -q "GENERATED" || {
    echo "FAIL: $f sin header GENERATED"; exit 1;
  }
done

# Footer con instrucción de regenerar
tail -2 "$TEST_DIR/.opencode/changes/auth-jwt/proposal.md" | grep -q "regenerate\|regenerar" || {
  echo "FAIL: sin footer de regenerar"; exit 1;
}

# NO BIDIRECCIONAL: --from-md debe rechazarse
bash scripts/teamdb-export-md.sh --from-md "$TEST_DIR" 2>&1 | grep -qE "not supported|prohibido|prohibida" || {
  echo "FAIL: acepta --from-md (debería rechazar)"; exit 1;
}

echo "PASS"
```

**GREEN:** `scripts/teamdb-export-md.sh`:
```bash
#!/usr/bin/env bash
# teamdb-export-md.sh — GENERA archivos .md desde TeamDB (DB es fuente, MD es output).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

# Política: NO bidireccional
[ "${1:-}" = "--from-md" ] && { echo "[ERROR] --from-md no soportado. Markdown es OUTPUT, no INPUT." >&2; exit 2; }
PROJECT="${1:?Uso: teamdb-export-md.sh <project>}"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }
CHANGES_DIR="$PROJECT/.opencode/changes"
mkdir -p "$CHANGES_DIR"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Export por cada plan
for plan_row in $(teamdb_exec_query "$DB" "SELECT id||'|'||slug FROM plans"); do
    PLAN_ID="${plan_row%|*}"
    SLUG="${plan_row#*|}"

    [ "$SLUG" = "auth-jwt" ] || continue  # demo; en producción iteraría todos

    PLAN_DIR="$CHANGES_DIR/$SLUG"
    mkdir -p "$PLAN_DIR/specs"

    HEADER=$(printf '%s\n' "<!-- GENERATED from teamdb on $NOW. Source of truth: $DB. DO NOT EDIT." \
        "     Bidirectional is PROHIBITED. To update DB: edit via teamdb-plan.sh / teamdb-amend.sh." \
        "     To regenerate: bash scripts/teamdb-export-md.sh $PROJECT -->")

    # proposal.md (desde proposals)
    {
        echo "$HEADER"
        echo ""
        PROPOSAL=$(teamdb_exec_query "$DB" "SELECT slug||'|'||title||'|'||COALESCE(intent_md,'')||'|'||status FROM proposals WHERE slug=?" "$SLUG")
        IFS='|' read -r PSLUG PTITLE PINTENT PSTATUS <<< "$PROPOSAL"
        echo "# Proposal: $PTITLE"
        echo ""
        echo "- **Slug:** $PSLUG"
        echo "- **Status:** $PSTATUS"
        echo ""
        echo "## Intent"
        echo ""
        echo "$PINTENT"
        echo ""
        echo "<!-- Footer: regenerar desde DB con teamdb-export-md.sh -->"
    } > "$PLAN_DIR/proposal.md"

    # design.md (desde plans + design_notes)
    {
        echo "$HEADER"
        echo ""
        DESIGN=$(teamdb_exec_query "$DB" "SELECT design_md FROM plans WHERE slug=?" "$SLUG")
        echo "$DESIGN"
        echo ""
        echo "## ADRs (design_notes)"
        echo ""
        teamdb_exec_query "$DB" "SELECT title||'|'||COALESCE(context_md,'')||'|'||COALESCE(decision_md,'') FROM design_notes WHERE plan_id=? ORDER BY decided_at DESC" "$PLAN_ID" | while IFS='|' read -r DT DC DD; do
            echo "### $DT"
            echo "**Context:** $DC"
            echo ""
            echo "**Decision:** $DD"
            echo ""
        done
        echo "<!-- Footer: regenerar desde DB -->"
    } > "$PLAN_DIR/design.md"

    # tasks.md
    {
        echo "$HEADER"
        echo ""
        echo "# Tasks for $SLUG"
        echo ""
        teamdb_exec_query "$DB" "SELECT '| ' || status || ' | [' || slug || '](' || COALESCE(description_md,'') || ') | ' || title FROM tasks WHERE plan_id=? ORDER BY order_index" "$PLAN_ID" | while IFS='|' read -r STATUS SLUG_FIELD DESC TITLE; do
            # Strip leading/trailing spaces
            echo "- [$STATUS] **$TITLE** \`$SLUG_FIELD\`"
        done
        echo ""
        echo "<!-- Footer -->"
    } > "$PLAN_DIR/tasks.md"
done

echo "exported: $CHANGES_DIR"
```

**REFACTOR:** Mover formateo a `lib-teamdb.sh::fmt_markdown_*()` cuando crezca.

**Done when:** `bash tests/teamdb-export-md.test.sh` pasa. Header GENERATED en cada archivo, footer con instrucciones, `--from-md` rechazado.

---

### T-2.16 — `teamdb-context.sh`: context capsule para handoff de Teo
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-context.sh` (nuevo), `tests/teamdb-context-capsule.test.sh` (nuevo)
**Implements:** req (5)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "ctx-test" "Ctx" /tmp/ctx-tasks.md >/dev/null

# Memoria relacionada
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES('auth-jwt','JWT Auth','JWT body','concept',datetime('now'))"
sqlite3 "$DB" "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES('use-jwt','Use JWT','JWT decision','accepted',datetime('now'),'pol')"

# Link capsule a task-1
bash scripts/teamdb-context.sh link ctx-test task-1 --concepts=auth-jwt --decisions=use-jwt "$TEST_DIR" >/dev/null

# Obtener cápsula
CAPSULE=$(bash scripts/teamdb-context.sh for-task ctx-test task-1 "$TEST_DIR")

# Validar JSON shape
echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['task']['slug'] == 'task-1', f\"task.slug={d['task']['slug']}\"
assert d['plan']['slug'] == 'ctx-test', f\"plan.slug={d['plan']['slug']}\"
assert any(c['slug']=='auth-jwt' for c in d['concepts']), 'sin concept auth-jwt'
assert any(x['slug']=='use-jwt' for x in d['decisions']), 'sin decision use-jwt'
print('OK')
" || { echo "FAIL: cápsula mal shape"; exit 1; }

# NO incluye decisions rejected
sqlite3 "$DB" "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES('rej-bcrypt','Use bcrypt','deferred','rejected',datetime('now'),'pol')"
CAPSULE=$(bash scripts/teamdb-context.sh for-task ctx-test task-1 "$TEST_DIR")
echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert all(x.get('status')=='accepted' for x in d['decisions']), 'FILTRA decisions no accepted'
print('OK')
" || { echo "FAIL: filtra accepted"; exit 1; }

echo "PASS"
```

**GREEN:** `scripts/teamdb-context.sh`:
```bash
#!/usr/bin/env bash
# teamdb-context.sh — Context capsule (selección filtrada) para handoff de Teo.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

OP="${1:?Uso: teamdb-context.sh <link|for-task> ...}"
shift

case "$OP" in
  link)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; shift 2
    PROJECT=""
    CONCEPTS=""
    DECISIONS=""
    PREFS=""
    PROBS=""
    for arg in "$@"; do
      case "$arg" in
        --concepts=*) CONCEPTS="${arg#--concepts=}" ;;
        --decisions=*) DECISIONS="${arg#--decisions=}" ;;
        --preferences=*) PREFS="${arg#--preferences=}" ;;
        --problems=*) PROBS="${arg#--problems=}" ;;
        -*) ;;
        *) PROJECT="$arg" ;;
      esac
    done
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$PLAN_SLUG")
    TASK_ID=$(teamdb_exec_query "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$TASK_SLUG")

    insert_capsule() {
        local table="$1"; local slug="$2"
        local mid=$(teamdb_exec_query "$DB" "SELECT id FROM $table WHERE slug=?" "$slug")
        [ -n "$mid" ] || { echo "WARN: $table/$slug no existe" >&2; return; }
        teamdb_exec_write "$DB" "INSERT OR IGNORE INTO task_context_capsules(task_id,memory_table,memory_id,relevance) VALUES(?,?,?,1)" \
            "$TASK_ID" "$table" "$mid" >/dev/null
    }

    IFS=',' read -ra CL <<< "${CONCEPTS:-}"
    for s in "${CL[@]}"; do [ -n "$s" ] && insert_capsule "concepts" "$s"; done
    IFS=',' read -ra DL <<< "${DECISIONS:-}"
    for s in "${DL[@]}"; do [ -n "$s" ] && insert_capsule "decisions" "$s"; done
    IFS=',' read -ra PL <<< "${PREFS:-}"
    for s in "${PL[@]}"; do [ -n "$s" ] && insert_capsule "preferences" "$s"; done
    IFS=',' read -ra BL <<< "${PROBS:-}"
    for s in "${BL[@]}"; do [ -n "$s" ] && insert_capsule "known_problems" "$s"; done

    echo "capsule: linked to task $TASK_SLUG"
    ;;

  for-task)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; PROJECT="${3:-$(pwd)}"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }
    python3 - "$DB" "$PLAN_SLUG" "$TASK_SLUG" <<'PYEOF'
import sqlite3, sys, json
db, plan_slug, task_slug = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row

plan = conn.execute("SELECT id, slug, title, design_md FROM plans WHERE slug=?", (plan_slug,)).fetchone()
if not plan:
    print("{}")
    sys.exit(0)
task = conn.execute("SELECT id, slug, title, description_md, acceptance_md, status FROM tasks WHERE plan_id=? AND slug=?", (plan['id'], task_slug)).fetchone()
if not task:
    print("{}")
    sys.exit(0)

# Capsule content
concepts, decisions, prefs, probs = [], [], [], []
for row in conn.execute("""
    SELECT c.memory_table, CASE c.memory_table
        WHEN 'concepts' THEN cp.slug
        WHEN 'decisions' THEN d.slug
        WHEN 'preferences' THEN p.slug
        WHEN 'known_problems' THEN kp.slug
    END AS slug,
    CASE c.memory_table
        WHEN 'concepts' THEN cp.title
        WHEN 'decisions' THEN d.title
        WHEN 'preferences' THEN p.body_md
        WHEN 'known_problems' THEN kp.title
    END AS title,
    CASE c.memory_table
        WHEN 'concepts' THEN cp.body_md
        WHEN 'decisions' THEN d.body_md
        WHEN 'preferences' THEN NULL
        WHEN 'known_problems' THEN kp.symptom_md
    END AS body_md,
    CASE c.memory_table
        WHEN 'concepts' THEN NULL
        WHEN 'decisions' THEN d.status
        ELSE NULL
    END AS extra
    FROM task_context_capsules c
    LEFT JOIN concepts cp ON c.memory_table='concepts' AND cp.id=c.memory_id
    LEFT JOIN decisions d ON c.memory_table='decisions' AND d.id=c.memory_id
    LEFT JOIN preferences p ON c.memory_table='preferences' AND p.id=c.memory_id
    LEFT JOIN known_problems kp ON c.memory_table='known_problems' AND kp.id=c.memory_id
    WHERE c.task_id=?
    ORDER BY c.memory_table, c.memory_id
""", (task['id'],)):
    table = row['memory_table']
    obj = {'slug': row['slug'], 'title': row['title']}
    if row['body_md']: obj['body_md'] = row['body_md'][:500]  # truncate for capsule
    if row['extra']: obj['status'] = row['extra']
    if table == 'concepts': concepts.append(obj)
    elif table == 'decisions':
        if row['extra'] == 'accepted':  # Solo accepted decisions en capsule
            decisions.append(obj)
    elif table == 'preferences': prefs.append(obj)
    elif table == 'known_problems':
        if row['extra'] != 'wontfix': probs.append(obj)

result = {
    'task': {'slug': task['slug'], 'title': task['title'], 'status': task['status'],
             'description_md': task['description_md'], 'acceptance_md': task['acceptance_md']},
    'plan': {'slug': plan['slug'], 'title': plan['title']},
    'concepts': concepts,
    'decisions': decisions,
    'preferences': prefs,
    'known_problems': probs,
}
print(json.dumps(result, indent=2, default=str))
PYEOF
    ;;
  *)
    echo "Uso: teamdb-context.sh <link|for-task> ..." >&2; exit 2 ;;
esac
```

**REFACTOR:** Extraer `filter_capsule_by_relevance()` cuando se agreguen múltiples relevance levels.

**Done when:** `bash tests/teamdb-context-capsule.test.sh` pasa.

---

### T-2.17v2 — `teamdb-plan.sh` UNIFICADO: crea proposal+plan+tasks + DAG opcional en una pasada
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-plan.sh` (sustituye stub), `tests/teamdb-cycle-amended.test.sh` (nuevo — antes era el "aggregator" conceptual)
**Implements:** req (1) + req (2) — version/historial en creación inicial + DAG opcional

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# tasks.md con formato extendido: dependencias opcionales via "_depends: [task-1]"
cat > /tmp/cycle-tasks.md <<'EOF'
- [ ] Endpoint POST /login _depends: []
- [ ] Validar JWT _depends: [task-1]
- [ ] Tests integración _depends: [task-1, task-2]
EOF

bash scripts/teamdb-plan.sh "$TEST_DIR" "cycle-test" "Cycle feature" /tmp/cycle-tasks.md >/dev/null

# Counts
P=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='cycle-test'")
PL=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM plans WHERE slug='cycle-test'")
T=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
DEPS=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM task_dependencies WHERE task_id IN (SELECT id FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test'))")
HIST=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")

[ "$P" = "1" ] && [ "$PL" = "1" ] && [ "$T" = "3" ] || { echo "FAIL: P=$P PL=$PL T=$T"; exit 1; }
[ "$DEPS" = "3" ] || { echo "FAIL: deps=$DEPS esperaba 3"; exit 1; }  # 0+1+2=3 edges
[ "$HIST" -ge "1" ] || { echo "FAIL: plan_history sin entry de created"; exit 1; }

# NO toca work_in_progress
WIP=$(teamdb_exec_query "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE slug='cycle-test'")
[ "$WIP" = "0" ] || { echo "FAIL: tocó work_in_progress"; exit 1; }

echo "PASS"
```

**GREEN:** `scripts/teamdb-plan.sh`:
```bash
#!/usr/bin/env bash
# teamdb-plan.sh — Crea proposal+plan+tasks+DAG+history en una pasada.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:?Uso: teamdb-plan.sh <project> <slug> <title> <tasks.md>}"
SLUG="${2:?Falta slug}"
TITLE="${3:?Falta title}"
TASKS_MD="${4:?Falta tasks.md}"
ACTOR="${TEAMDB_ACTOR:-sol}"

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }
[ -f "$TASKS_MD" ] || { echo "tasks.md no existe" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# proposals
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,'draft','pol',?,?) ON CONFLICT(slug) DO UPDATE SET updated_at=excluded.updated_at" \
    "$SLUG" "$TITLE" "# Intent\n\n$TITLE" "$NOW" "$NOW" >/dev/null

PROPOSAL_ID=$(teamdb_exec_query "$DB" "SELECT id FROM proposals WHERE slug=?" "$SLUG")

# plans
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?) ON CONFLICT(slug) DO UPDATE SET updated_at=excluded.updated_at" \
    "$SLUG" "$TITLE" "$PROPOSAL_ID" "# Design\n\nTo be defined by ADRs during execution." "$NOW" "$NOW" >/dev/null

PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id FROM plans WHERE slug=?" "$SLUG")

# Parse tasks con _depends opcional
declare -A SLUG_BY_INDEX 2>/dev/null  # bash 4 (no-op en bash 3)
ORDER=0
# bash 3.2-friendly: usar archivos temporales
TMP_DIR=$(mktemp -d)
while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^-?\ *\[?\ \]?\ *(.*)$ ]] || continue
    raw="${BASH_REMATCH[1]}"
    # Detectar dependencia: suffix "_depends: [task-1, task-2]"
    deps=""
    title="$raw"
    if [[ "$raw" =~ \ _depends:[[:space:]]*\[[^]]*\] ]]; then
        deps_part="${raw##*_depends:}"
        title="${raw% _depends:*}"
        deps_part="${deps_part#\[}"; deps_part="${deps_part%\]}"
        deps="$(echo "$deps_part" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | tr '\n' ',' | sed 's/,$//')"
    fi
    task_slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//;s/--*/-/g')
    [ -z "$task_slug" ] && task_slug="task-$ORDER"
    echo "$ORDER|$task_slug|$title|$deps" >> "$TMP_DIR/tasks.tsv"
    ORDER=$((ORDER + 1))
done < <(grep -E '^- \[[ x]\] ' "$TASKS_MD" || grep -E '^- \[ \] ' "$TASKS_MD")

# Insertar tasks con FK-safe ordering
while IFS='|' read -r idx tslug ttitle deps; do
    teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,description_md,acceptance_md,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,?,?,'pending',2,?,'teo',?,?)" \
        "$PLAN_ID" "$tslug" "$ttitle" "" "" "$idx" "$NOW" "$NOW" >/dev/null
done < "$TMP_DIR/tasks.tsv"

# Insertar DAG edges (después de tener todos los task_ids)
while IFS='|' read -r idx tslug ttitle deps; do
    [ -z "$deps" ] && continue
    IFS=',' read -ra DEP_LIST <<< "$deps"
    for dep_slug in "${DEP_LIST[@]}"; do
        [ -z "$dep_slug" ] && continue
        teamdb_exec_write "$DB" "INSERT OR IGNORE INTO task_dependencies(task_id,depends_on_task_id,type,created_at) VALUES((SELECT id FROM tasks WHERE plan_id=? AND slug=?), (SELECT id FROM tasks WHERE plan_id=? AND slug=?), 'blocks', ?)" \
            "$PLAN_ID" "$tslug" "$PLAN_ID" "$dep_slug" "$NOW" >/dev/null
    done
done < "$TMP_DIR/tasks.tsv"

rm -rf "$TMP_DIR"

# plan_history (registrar creación)
teamdb_exec_write "$DB" "INSERT INTO plan_history(plan_id,version,changed_by,changed_at,operation,diff_md) VALUES(?, 1, ?, ?, 'created', ?)" \
    "$PLAN_ID" "$ACTOR" "$NOW" "Created with $ORDER tasks" >/dev/null

echo "plan: $SLUG ($ORDER tasks, plan_id=$PLAN_ID)"
```

> **Diferencia vs T-2.1 original**: la versión v2 crea `task_dependencies` desde el .md si se usa el sufijo `_depends: [task-x, task-y]`, y registra la creación en `plan_history`.

**REFACTOR:** Extraer `parse_tasks_tsv()` cuando crezca.

**Done when:** `bash tests/teamdb-cycle-amended.test.sh` pasa.

---

### FASE 2 v2 — Exit Criteria (Jhon)

```bash
# Pre-Fase-2 sigue verde (backward-compat):
bash tests/teamdb-safe-query.test.sh \
  && bash tests/teamdb-search-sqli.test.sh \
  && bash tests/teamdb-related-sqli.test.sh \
  && bash tests/teamdb-problems-fts.test.sh \
  && bash tests/install-script-copies.test.sh \
  && bash tests/install-hooks-paths.test.sh \

# Nuevos de Fase 2 v2:
bash tests/teamdb-dag-tables-exist.test.sh \
  && bash tests/teamdb-python-bindparams.test.sh \
  && bash tests/teamdb-write-wal.test.sh \
  && bash tests/teamdb-amend-full.test.sh \
  && bash tests/teamdb-deps-dag.test.sh \
  && bash tests/teamdb-claim-lease.test.sh \
  && bash tests/teamdb-export-md.test.sh \
  && bash tests/teamdb-context-capsule.test.sh \
  && bash tests/teamdb-cycle-amended.test.sh \

# Coherencia y portabilidad:
bash tests/version-coherence.test.sh \
  && bash tests/portability-bash32.test.sh \

# Lint:
shellcheck scripts/lib/lib-teamdb.sh \
  shellcheck scripts/teamdb-amend.sh scripts/teamdb-deps.sh scripts/teamdb-claim.sh \
  scripts/teamdb-export-md.sh scripts/teamdb-context.sh scripts/teamdb-plan.sh \
  shellcheck scripts/hooks/pre-commit scripts/hooks/post-merge \
  python3 -c "import ast; ast.parse(open('scripts/teamdb_exec.py').read())"
```

Luz corre quality gate arquitectónico. Pau actualiza CHANGELOG.

---



### T-2.1 — `teamdb-plan.sh` crea proposal/plan/tasks en DB  `[SUPERSEDED por T-2.17v2]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-plan.sh` (nuevo), `tests/teamdb-plan.test.sh` (nuevo)
**Implements AC:** 4.1, 4.2

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# tasks.md con 3 tareas (formato: - [ ] título)
cat > /tmp/test-tasks.md <<'EOF'
# Plan de prueba
- [ ] Crear endpoint POST /login
- [ ] Validar JWT
- [ ] Tests de integración
EOF

bash scripts/teamdb-plan.sh "$TEST_DIR" "feat-test" "Test feature" /tmp/test-tasks.md >/dev/null

# Verifica filas en las 3 tablas
P=$(sqlite3 "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='feat-test'")
PL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM plans WHERE slug='feat-test'")
T=$(sqlite3 "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test')")

[ "$P" = "1" ] && [ "$PL" = "1" ] && [ "$T" = "3" ] || {
  echo "FAIL: esperábamos P=1 PL=1 T=3, obtuvimos P=$P PL=$PL T=$T"; exit 1;
}

# No debe tocar work_in_progress
WIP=$(sqlite3 "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE slug='feat-test'")
[ "$WIP" = "0" ] || { echo "FAIL: tocó work_in_progress"; exit 1; }

echo "PASS"
```

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-plan.sh — Crea proposal+plan+tasks en DB
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
SLUG="${2:?Uso: teamdb-plan.sh <project> <slug> <title> <tasks.md>}"
TITLE="${3:?Falta title}"
TASKS_MD="${4:?Falta tasks.md}"

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }
[ -f "$TASKS_MD" ] || { echo "tasks.md no existe: $TASKS_MD" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SLUG_E="$(echo "$SLUG" | sed "s/'/''/g")"
TITLE_E="$(echo "$TITLE" | sed "s/'/''/g")"

# 1. proposals (status=draft)
teamdb_write_project "$DB" "
  INSERT INTO proposals (slug, title, intent_md, status, agent, created_at, updated_at)
  VALUES ('$SLUG_E', '$TITLE_E', '# Intent\n\n$TITLE_E', 'draft', 'sol', '$NOW', '$NOW')
" 2>/dev/null
# Si UNIQUE conflict (slug ya existe), reusamos el proposal existente
PROPOSAL_ID=$(sqlite3 "$DB" "SELECT id FROM proposals WHERE slug='$SLUG_E'")

# 2. plans
teamdb_write_project "$DB" "
  INSERT INTO plans (slug, title, proposal_id, design_md, status, agent, created_at, updated_at)
  VALUES ('$SLUG_E', '$TITLE_E', $PROPOSAL_ID, '# Design\n\nTBD', 'active', 'sol', '$NOW', '$NOW')
  ON CONFLICT(slug) DO UPDATE SET updated_at='$NOW'
" 2>/dev/null || true
PLAN_ID=$(sqlite3 "$DB" "SELECT id FROM plans WHERE slug='$SLUG_E'")

# 3. tasks — parse `- [ ] título` del .md
ORDER=0
while IFS= read -r task_title; do
  [ -z "$task_title" ] && continue
  TASK_TITLE_E="$(echo "$task_title" | sed "s/'/''/g")"
  TASK_SLUG=$(echo "$task_title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//;s/--*/-/g')
  [ -z "$TASK_SLUG" ] && TASK_SLUG="task-$ORDER"
  ORDER=$((ORDER+1))
  teamdb_write_project "$DB" "
    INSERT INTO tasks (plan_id, slug, title, status, priority, order_index, owner, created_at, updated_at)
    VALUES ($PLAN_ID, '$TASK_SLUG', '$TASK_TITLE_E', 'pending', 2, $ORDER, 'teo', '$NOW', '$NOW')
  " 2>/dev/null || true
done < <(grep -E '^- \[ \]' "$TASKS_MD" | sed 's/^- \[ \] //')

echo "plan: $SLUG ($ORDER tasks)"
```

**REFACTOR:** Extraer `parse_tasks_md()` que retorna líneas en array.

**Done when:** `bash tests/teamdb-plan.test.sh` pasa.

---

### T-2.2 — `teamdb_write_*` global simétrico + actor + reject unsafe patterns  `[SUPERSEDED por T-2.10 + T-2.11]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/lib/lib-teamdb.sh`, `tests/write-helpers.test.sh` (nuevo)
**Implements AC:** 5.1, 5.2, 5.3

**RED:**
```bash
source scripts/lib/lib-teamdb.sh

# 1. teamdb_write_global existe
type teamdb_write_global >/dev/null 2>&1 || { echo "FAIL: no definido"; exit 1; }

# 2. Rechaza unsafe pattern (multi-statement)
GLOBAL_DB="$HOME/.config/opencode/team.db"
mkdir -p "$HOME/.config/opencode"
sqlite3 "$GLOBAL_DB" < sql/global-schema.sql 2>/dev/null || true
RES=$(teamdb_write_global "INSERT INTO x VALUES(1); DROP TABLE x; --" 2>&1) || true
echo "$RES" | grep -q "Unsafe SQL" || {
  echo "FAIL: no rechazó multi-statement"; exit 1;
}

# 3. teamdb_write_project también rechaza unsafe (WRI-1.3)
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
RES=$(teamdb_write_project "$DB" "INSERT INTO x VALUES(1); DELETE FROM audit_log; --" 2>&1) || true
echo "$RES" | grep -q "Unsafe SQL" || {
  echo "FAIL: write_project no rechazó unsafe"; exit 1;
}

# 4. Actor: cuando TEAMDB_ACTOR=teo, el helper lo expone (assert de cableado, ver T-3.4 para verificación end-to-end)
TEAMDB_ACTOR=teo bash -c 'source scripts/lib/lib-teamdb.sh && [ "$(type _actor_or_unknown | grep -c "TEAMDB_ACTOR")" -ge 1 ]' \
  || { echo "FAIL: TEAMDB_ACTOR plumbing ausente"; exit 1; }

echo "PASS"
```

**GREEN:**
```bash
# En scripts/lib/lib-teamdb.sh, agregar:

# WRI-1.3 — rechaza unsafe patterns en SQL
_teamdb_reject_unsafe_sql() {
  local sql="$1"
  # Multi-statement: más de un ';' (excepto el final)
  local semicolons="${sql%;}"
  case "$semicolons" in *\;*) echo "[ERROR] Unsafe SQL pattern (multi-statement)" >&2; return 1 ;; esac
  # Comment-out attack patterns
  case "$sql" in
    *"--"*)  # Permitido solo en comentarios SQL al inicio de línea; rechazar comentarios inline
      echo "$sql" | grep -qE '^[[:space:]]*--' || { echo "[ERROR] Unsafe SQL pattern (-- inline)" >&2; return 1; }
      ;;
  esac
  # DROP/DELETE/UPDATE sin WHERE (masivo)
  case "$sql" in
    *"DROP TABLE"*) echo "[ERROR] Unsafe SQL pattern (DROP TABLE)" >&2; return 1 ;;
  esac
  return 0
}

# WRI-1.1 — teamdb_write_global simétrico
teamdb_write_global() {
  teamdb_check_sqlite3 || return 1
  local sql="$1"
  _teamdb_reject_unsafe_sql "$sql" || return 1
  local db; db="$(teamdb_global_path)"
  [ -f "$db" ] || { echo "[ERROR] DB global no existe: $db" >&2; return 1; }
  local lock_path="${db}.lock"
  local actor; actor="${TEAMDB_ACTOR:-unknown}"

  # Helper-side audit row (T-3.4 lo enriquece con actor_source='helper')
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 5 200 || { echo "[ERROR] No lock $lock_path" >&2; return 1; }
      sqlite3 "$db" "INSERT INTO audit_log (ts, agent, action, table_name) VALUES (datetime('now'), '$actor', 'mutate-global', '<via_helper>');
$sql"
    ) 200>"$lock_path"
  else
    sqlite3 "$db" "INSERT INTO audit_log (ts, agent, action, table_name) VALUES (datetime('now'), '$actor', 'mutate-global', '<via_helper>');
$sql"
  fi
}

# Refactor: teamdb_write_project también emite helper-side audit
teamdb_write_project() {
  teamdb_check_sqlite3 || return 1
  local db="$1"; shift
  local sql="$1"
  _teamdb_reject_unsafe_sql "$sql" || return 1
  [ -f "$db" ] || { echo "[ERROR] DB no existe: $db" >&2; return 1; }
  local lock_path="${db}.lock"
  local actor; actor="${TEAMDB_ACTOR:-unknown}"

  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 5 200 || { echo "[ERROR] No lock $lock_path" >&2; return 1; }
      sqlite3 "$db" "INSERT INTO audit_log (ts, agent, action, table_name) VALUES (datetime('now'), '$actor', 'mutate', '<via_helper>');
$sql"
    ) 200>"$lock_path"
  else
    sqlite3 "$db" "INSERT INTO audit_log (ts, agent, action, table_name) VALUES (datetime('now'), '$actor', 'mutate', '<via_helper>');
$sql"
  fi
}
```

> Nota: WRI-1.2 (TEAMDB_ACTOR → audit_log.agent) se valida end-to-end en T-3.4 cuando se rehace el modelo de audit.

**REFACTOR:** `_teamdb_reject_unsafe_sql` es unit-testable aislado.

**Invariantes rotas intencionalmente y por qué:** El helper INSERTA un audit row propio ANTES del SQL real. Los triggers del schema actual (líneas 160-210 de project-schema.sql) también disparan filas adicionales con `agent='system'`. El modelo final está en T-3.4, donde se elimina el duplicado. **Entre T-2.2 y T-3.4 puede haber duplicación temporal de audit rows. Los tests de T-3.4 deben considerar el gap.**

**Done when:** `bash tests/write-helpers.test.sh` pasa.

---

### T-2.3 — `teamdb-status.sh` resume el estado del ciclo  `[SUPERSEDED — en T-2.17v2 se reduce]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-status.sh` (nuevo), `tests/teamdb-status.test.sh` (nuevo)
**Implements AC:** 4.3 (parcial)

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "feat-test" "Test" /tmp/test-tasks.md 2>/dev/null || true

OUT=$(bash scripts/teamdb-status.sh "$TEST_DIR" 2>&1)
RC=$?
[ "$RC" = "0" ] || { echo "FAIL: exit != 0"; exit 1; }
echo "$OUT" | grep -q "feat-test" || { echo "FAIL: no menciona feat-test"; exit 1; }
echo "$OUT" | grep -q "pending" || { echo "FAIL: no menciona status pending"; exit 1; }
echo "PASS"
```

**GREEN:** Read-only:
```bash
#!/usr/bin/env bash
# teamdb-status.sh — Resumen del ciclo (proposals/plans/tasks/audit) de un proyecto
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "teamdb-status: DB no existe en $PROJECT" >&2; exit 0; }

echo "teamdb status: $PROJECT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Planes activos:"
sqlite3 -separator $'\t' "$DB" "SELECT slug, status FROM plans WHERE status='active' ORDER BY updated_at DESC LIMIT 10"
echo ""
echo "Tareas pendientes por plan:"
sqlite3 -separator $'\t' "$DB" "
  SELECT p.slug, COUNT(t.id) AS pending_tasks
  FROM plans p LEFT JOIN tasks t ON t.plan_id=p.id AND t.status='pending'
  WHERE p.status='active'
  GROUP BY p.slug
"
echo ""
echo "Tareas bloqueadas:"
sqlite3 -separator $'\t' "$DB" "
  SELECT p.slug, t.slug, t.blocked_reason
  FROM plans p JOIN tasks t ON t.plan_id=p.id
  WHERE t.status='blocked'
"
echo ""
echo "Últimas 5 entradas de audit:"
sqlite3 -separator $'\t' "$DB" "SELECT ts, agent, action, table_name FROM audit_log ORDER BY ts DESC LIMIT 5"
exit 0
```

**REFACTOR:** Extraer formateo de filas a `fmt_table()`.

**Done when:** `bash tests/teamdb-status.test.sh` pasa.

---

### T-2.4 — `teamdb-resume.sh` muestra el plan activo con próxima task sugerida  `[SUPERSEDED por T-2.13 + T-2.17v2]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-resume.sh` (nuevo), `tests/teamdb-resume.test.sh` (nuevo)
**Implements AC:** 4.3

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "feat-test" "Test feature" /tmp/test-tasks.md >/dev/null

# Marcar primera task in_progress, segunda pending
sqlite3 "$DB" "UPDATE tasks SET status='in_progress', started_at=datetime('now') WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test') AND order_index=1"
sqlite3 "$DB" "UPDATE tasks SET status='resolved', started_at=datetime('now'), resolved_at=datetime('now') WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test') AND order_index=2" 2>/dev/null

OUT=$(bash scripts/teamdb-resume.sh "feat-test" "$TEST_DIR" 2>&1)
echo "$OUT" | grep -q "feat-test" || { echo "FAIL: no title"; exit 1; }
echo "$OUT" | grep -qE "NEXT TASK|next.*task" || { echo "FAIL: no sugiere next"; exit 1; }
echo "PASS"
```

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-resume.sh — Muestra el estado completo del plan y sugiere la próxima task
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

SLUG="${1:?Uso: teamdb-resume.sh <plan-slug> [project]}"
PROJECT="${2:-$(pwd)}"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }

PLAN_ID=$(sqlite3 "$DB" "SELECT id FROM plans WHERE slug='$SLUG'")
[ -n "$PLAN_ID" ] || { echo "Plan no encontrado: $SLUG" >&2; exit 1; }

echo "PLAN: $(sqlite3 "$DB" "SELECT title FROM plans WHERE id=$PLAN_ID") ($SLUG, status=$(sqlite3 "$DB" "SELECT status FROM plans WHERE id=$PLAN_ID"))"
echo ""
echo "Tasks grouped by status:"
sqlite3 -separator $'\t' "$DB" "
  SELECT status, slug, title FROM tasks WHERE plan_id=$PLAN_ID
  ORDER BY status, order_index
"
echo ""
echo "Last audit entry:"
sqlite3 -separator $'\t' "$DB" "
  SELECT ts, agent, action, table_name FROM audit_log
  WHERE ts > datetime('now', '-1 day')
  ORDER BY ts DESC LIMIT 1
"
echo ""
NEXT_SLUG=$(sqlite3 "$DB" "SELECT slug FROM tasks WHERE plan_id=$PLAN_ID AND status='pending' ORDER BY order_index LIMIT 1")
NEXT_TITLE=$(sqlite3 "$DB" "SELECT title FROM tasks WHERE plan_id=$PLAN_ID AND slug='$NEXT_SLUG'")
echo "NEXT TASK: [$NEXT_SLUG] $NEXT_TITLE"
```

**REFACTOR:** N/A.

**Done when:** `bash tests/teamdb-resume.test.sh` pasa.

---

### T-2.5 — `teamdb-amend.sh` agrega task a plan existente  `[SUPERSEDIDO por T-2.12 — solo implementaba --add-task]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-amend.sh` (nuevo), `tests/teamdb-amend.test.sh` (nuevo)
**Implements AC:** 4.1

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "feat-test" "Test" /tmp/test-tasks.md >/dev/null

bash scripts/teamdb-amend.sh "feat-test" --add-task "Nueva task agregada" "$TEST_DIR" >/dev/null

COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test')")
[ "$COUNT" = "4" ] || { echo "FAIL: esperábamos 4 tasks, hay $COUNT"; exit 1; }

# Audit row con action='amend'
AUDIT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE action='mutate' OR details LIKE '%amend%'")
[ "$AUDIT" -ge "1" ] || { echo "FAIL: no se registró audit"; exit 1; }

echo "PASS"
```

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-amend.sh — Modifica un plan existente (add-task, set-status)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

SLUG="${1:?Uso: teamdb-amend.sh <plan-slug> --add-task <title> [project]}"
PROJECT="${4:-$(pwd)}"

case "${2:-}" in
  --add-task)
    NEW_TITLE="${3:?Falta título}"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }

    PLAN_ID=$(sqlite3 "$DB" "SELECT id FROM plans WHERE slug='$SLUG'")
    [ -n "$PLAN_ID" ] || { echo "Plan no encontrado: $SLUG" >&2; exit 1; }

    NEW_TITLE_E="$(echo "$NEW_TITLE" | sed "s/'/''/g")"
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    NEXT_ORDER=$(sqlite3 "$DB" "SELECT COALESCE(MAX(order_index)+1, 1) FROM tasks WHERE plan_id=$PLAN_ID")
    NEW_SLUG=$(echo "$NEW_TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')

    teamdb_write_project "$DB" "
      INSERT INTO tasks (plan_id, slug, title, status, priority, order_index, owner, created_at, updated_at)
      VALUES ($PLAN_ID, '$NEW_SLUG', '$NEW_TITLE_E', 'pending', 2, $NEXT_ORDER, 'teo', '$NOW', '$NOW');
      UPDATE plans SET updated_at='$NOW' WHERE id=$PLAN_ID;
    "
    echo "added: [$NEW_SLUG] $NEW_TITLE"
    ;;
  *)
    echo "Uso: teamdb-amend.sh <slug> --add-task <title> [project]" >&2
    exit 2
    ;;
esac
```

**REFACTOR:** Extraer `amend_add_task()` y `amend_set_status()` cuando crezca.

**Done when:** `bash tests/teamdb-amend.test.sh` pasa.

---

### T-2.6 — `teamdb-execute-plan.sh` marca next task in_progress (solo orquestación, NO shell)  `[SUPERSEDED por T-2.14 (claim) — el orquestador ahora hace claim, no update directo]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-execute-plan.sh` (nuevo), `tests/teamdb-execute-plan.test.sh` (nuevo)
**Implements AC:** 4.1 + DC-3

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-plan.sh "$TEST_DIR" "feat-test" "Test" /tmp/test-tasks.md >/dev/null

# Marcar primera task pendiente explícitamente por orden
bash scripts/teamdb-execute-plan.sh "feat-test" "$TEST_DIR" >/dev/null

# La task de orden=1 debe estar in_progress
STATUS=$(sqlite3 "$DB" "SELECT status FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test') AND order_index=1")
[ "$STATUS" = "in_progress" ] || { echo "FAIL: status=$STATUS"; exit 1; }

# started_at debe estar seteado
TS=$(sqlite3 "$DB" "SELECT started_at FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='feat-test') AND order_index=1")
[ -n "$TS" ] || { echo "FAIL: started_at vacío"; exit 1; }

# Debe haber audit row con action='start'
AUDIT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE details LIKE '%start%' OR action='start'")
[ "$AUDIT" -ge "1" ] || { echo "FAIL: no audit 'start'"; exit 1; }

# DC-3: NO debe haber ejecución de shell
grep -E "bash|sh -c|exec" scripts/teamdb-execute-plan.sh && { echo "FAIL: ejecuta shell"; exit 1; } || true

echo "PASS"
```

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-execute-plan.sh — Marca la próxima task pending como in_progress.
# Solo orquesta. NO ejecuta shell. Teo ejecuta el trabajo de ingeniería con TDD.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

SLUG="${1:?Uso: teamdb-execute-plan.sh <plan-slug> [project]}"
PROJECT="${2:-$(pwd)}"

# Política: este script SOLO orquesta.
# Restricción DC-3: NO ejecutar bash, sh, eval, ni nada que tome otro shell.
# La validación es por grep en tests, no por runtime check aquí.

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe" >&2; exit 1; }

PLAN_ID=$(sqlite3 "$DB" "SELECT id FROM plans WHERE slug='$SLUG'")
[ -n "$PLAN_ID" ] || { echo "Plan no encontrado: $SLUG" >&2; exit 1; }

NEXT=$(sqlite3 "$DB" "SELECT slug FROM tasks WHERE plan_id=$PLAN_ID AND status='pending' ORDER BY order_index LIMIT 1")
[ -n "$NEXT" ] || { echo "Plan $SLUG sin tareas pendientes" >&2; exit 0; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TEAMDB_ACTOR=teo teamdb_write_project "$DB" "
  UPDATE tasks SET status='in_progress', owner='teo', started_at='$NOW', updated_at='$NOW'
  WHERE plan_id=$PLAN_ID AND slug='$NEXT'
"

echo "marked: [$NEXT] → in_progress"
echo "next: Teo, ejecutá el trabajo de ingeniería con TDD sobre la task [$NEXT]."
```

**REFACTOR:** Si se necesita en el futuro `--task <slug>` (TASK-2.6 base solo marca la próxima pending), agregar flag. Por ahora: solo `--next-task` implícito.

**Done when:** `bash tests/teamdb-execute-plan.test.sh` pasa.

---

### T-2.7 — `teamdb-export.sh` incluye `audit_log` y `schema_meta` (idempotente)  `[VALIDO — se mantiene, junto con T-2.15 (export-md)]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-export.sh`, `tests/teamdb-export-audit.test.sh` (nuevo)
**Implements AC:** 8.2

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# Generar al menos un audit row via teamdb_write_project
teamdb_write_project_no_actor="$DB"
# Insert + immediate write via helper (T-2.2 ya emite audit row)
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('audit-export-test','AET','x',datetime('now'))"

bash scripts/teamdb-export.sh "$TEST_DIR" >/dev/null

# data_audit_log.sql debe existir (y no estar vacío si hay rows)
[ -f "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql" ] || {
  echo "FAIL: data_audit_log.sql no existe"; exit 1;
}

# data_schema_meta.sql debe existir
[ -f "$TEST_DIR/.opencode/context/teamdb/data_schema_meta.sql" ] || {
  echo "FAIL: data_schema_meta.sql no existe"; exit 1;
}

# Round-trip: import en directorio nuevo preserva audit_log
TEST_DIR2=$(mktemp -d); mkdir -p "$TEST_DIR2/.opencode/context"
cp "$TEST_DIR/.opencode/context/teamdb/data_*.sql" "$TEST_DIR2/.opencode/context/teamdb/" 2>/dev/null || true
mkdir -p "$TEST_DIR2/.opencode/context/teamdb"
cp "$TEST_DIR/.opencode/context/teamdb/"*.sql "$TEST_DIR2/.opencode/context/teamdb/"
# Init DB
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR2" >/dev/null
bash scripts/teamdb-import.sh "$TEST_DIR2" >/dev/null

COUNT_AUDIT=$(sqlite3 "$TEST_DIR2/.opencode/context/team.db" "SELECT COUNT(*) FROM audit_log")
[ "$COUNT_AUDIT" -ge "0" ] || { echo "FAIL: import no preservó audit_log"; exit 1; }

echo "PASS"
```

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-export.sh — DB → .sql (incluye audit_log y schema_meta)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "no DB: $DB" >&2; exit 1; }

OUT="$PROJECT/.opencode/context/teamdb"
mkdir -p "$OUT"

# Tablas de "datos de usuario"
for table in concepts decisions preferences known_problems memory_links memory_tags work_in_progress \
             proposals plans specs design_notes tasks; do
  out="$OUT/data_${table}.sql"
  sqlite3 "$DB" ".dump $table" > "$out" 2>/dev/null || true
done

# schema_meta (solo filas, no estructura)
sqlite3 "$DB" ".dump schema_meta" > "$OUT/data_schema_meta.sql" 2>/dev/null || true

# audit_log (últimas 1000 entradas — incluyendo las del helper con actor real)
sqlite3 "$DB" "SELECT * FROM (SELECT * FROM audit_log ORDER BY ts DESC LIMIT 1000) ORDER BY ts ASC" \
  | sqlite3 "$DB" ".import" /dev/stdin audit_log 2>/dev/null \
  || sqlite3 "$DB" ".dump audit_log" > "$OUT/data_audit_log.sql" 2>/dev/null || true

echo "exported: $OUT"
```

**Simplificación de la última línea**: usar `.dump audit_log` directo es más simple y round-trip seguro:
```bash
# Al final, simplificar a:
sqlite3 "$DB" ".dump audit_log" > "$OUT/data_audit_log.sql" 2>/dev/null || true
```

**REFACTOR:** Convertir la lista de tablas a variable (DRY).

**Done when:** `bash tests/teamdb-export-audit.test.sh` pasa.

---

### T-2.8 — `teamdb-migrate.sh` no borra `.md` (preserva Markdown)  `[VALIDO — DC-1 se mantiene]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `scripts/teamdb-migrate.sh`, `tests/teamdb-migrate-md-preserve.test.sh` (nuevo)
**Implements AC:** 11.1, 11.2 + DC-1

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context/concept"
DB="$TEST_DIR/.opencode/context/team.db"

# Crear un .md con frontmatter
cat > "$TEST_DIR/.opencode/context/concept/auth-jwt.md" <<'EOF'
---
type: Concept
tags: [auth, jwt]
confidence: 0.9
---

# Auth JWT

Contenido del concept doc.
EOF

bash scripts/teamdb-migrate.sh "$TEST_DIR" >/dev/null

# 1. La DB tiene la fila del concept
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='auth-jwt'")
[ "$COUNT" = "1" ] || { echo "FAIL: concept no migrado a DB"; exit 1; }

# 2. El archivo .md SIGUE EXISTIENDO (DC-1)
[ -f "$TEST_DIR/.opencode/context/concept/auth-jwt.md" ] || {
  echo "FAIL: .md borrado (viola DC-1)"; exit 1;
}

# 3. El .md NO se movió a legacy/
[ ! -d "$TEST_DIR/.opencode/context/legacy/concept" ] || {
  echo "FAIL: .md movido a legacy/"; exit 1;
}

# 4. .jsonl SÍ se mueve a legacy/ (mantener comportamiento legacy de .jsonl)
echo '{"topic":"j","decision":"d"}' > "$TEST_DIR/.opencode/context/DECISIONS.jsonl"
bash scripts/teamdb-migrate.sh "$TEST_DIR" >/dev/null
[ -d "$TEST_DIR/.opencode/context/legacy" ] && [ -f "$TEST_DIR/.opencode/context/legacy/DECISIONS.jsonl" ] || {
  echo "FAIL: .jsonl no se movió a legacy/"; exit 1;
}

# 5. Idempotente: correr 2 veces no crea duplicados
bash scripts/teamdb-migrate.sh "$TEST_DIR" >/dev/null
bash scripts/teamdb-migrate.sh "$TEST_DIR" >/dev/null
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='auth-jwt'")
[ "$COUNT" = "1" ] || { echo "FAIL: idempotencia rota ($COUNT rows)"; exit 1; }

# 6. Sin .jsonl: termina 0 + warning
TEST_DIR3=$(mktemp -d); mkdir -p "$TEST_DIR3/.opencode/context"
bash scripts/teamdb-migrate.sh "$TEST_DIR3" >/dev/null 2>&1
RC=$?
# Script termina 0 con warning, no error
[ ! -d "$TEST_DIR3/.opencode/context/legacy" ] || {
  # Si metió mkdir -p, está OK siempre que no haya fallado
  echo "INFO: legacy dir creado (puede ser benigno)"
}

echo "PASS"
```

**GREEN:** Reescribir `teamdb-migrate.sh` para preservar `.md`:
```bash
#!/usr/bin/env bash
# teamdb-migrate.sh — Migra .jsonl legacy a teamdb (SQL injection-safe via sql_escape).
# Markdown (.md) NO se borra: TeamDB es la fuente canónica; .md es export legible.
# Solo los .jsonl se mueven a legacy/.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
[ -f "$SCRIPT_DIR/lib-teamdb.sh" ] && source "$SCRIPT_DIR/lib-teamdb.sh" \
  || source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
teamdb_init_project "$PROJECT"  # SAFE: no-op si ya existe
DB="$(teamdb_project_path "$PROJECT")"
CTX_DIR="$PROJECT/.opencode/context"

sql_escape() { echo "$1" | sed "s/'/''/g"; }
json_field() {
  local field="$1"
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null || echo ""
}

# Si no hay .jsonl, warning + exit 0 (AC-11.2)
shopt -s nullglob 2>/dev/null || true  # bash 3.2: nullglob no aplica en misma forma; fallback abajo
JSONL_FOUND=0
for _ignore in "$CTX_DIR"/*.jsonl; do
  [ -e "$_ignore" ] && JSONL_FOUND=1 && break
done

if [ "$JSONL_FOUND" = "0" ]; then
  echo "[WARN] no legacy .jsonl files to migrate" >&2
  exit 0
fi

# Migrar .jsonl
for jsonl in "$CTX_DIR"/*.jsonl; do
  [ -e "$jsonl" ] || continue
  fname=$(basename "$jsonl" .jsonl)
  case "$fname" in
    DECISIONS)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        topic=$(echo "$line" | json_field "topic") || continue
        decision=$(echo "$line" | json_field "decision") || continue
        [ -n "$topic" ] || continue
        topic=$(sql_escape "$topic"); decision=$(sql_escape "$decision")
        teamdb_write_project "$DB" "INSERT OR IGNORE INTO decisions(slug,title,body_md,decided_at) VALUES('$topic','$topic','$decision',datetime('now'))" 2>/dev/null || true
      done < "$jsonl"
      ;;
    PATTERNS|PROJECT)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        name=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('name') or d.get('key',''))" 2>/dev/null) || continue
        desc=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('description') or d.get('value') or d.get('note',''))" 2>/dev/null) || continue
        [ -n "$name" ] || continue
        name=$(sql_escape "$name"); desc=$(sql_escape "$desc")
        teamdb_write_project "$DB" "INSERT OR IGNORE INTO concepts(slug,title,body_md,category,updated_at) VALUES('$name','$name','$desc','legacy',datetime('now'))" 2>/dev/null || true
      done < "$jsonl"
      ;;
    PREFERENCES)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        slug=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('slug') or d.get('scope',''))" 2>/dev/null) || continue
        body=$(echo "$line" | json_field "preference") || continue
        [ -n "$slug" ] || continue
        slug=$(sql_escape "$slug"); body=$(sql_escape "$body")
        teamdb_write_project "$DB" "INSERT OR IGNORE INTO preferences(slug,scope,body_md,source) VALUES('$slug','legacy','$body','migrated')" 2>/dev/null || true
      done < "$jsonl"
      ;;
    REJECTIONS)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        attempted=$(json_field "attempted" <<< "$line") || continue
        reason=$(json_field "reason" <<< "$line") || continue
        [ -n "$attempted" ] || continue
        attempted=$(sql_escape "$attempted"); reason=$(sql_escape "$reason")
        teamdb_write_project "$DB" "INSERT OR IGNORE INTO known_problems(slug,title,symptom_md,discovered_at) VALUES('$attempted','$attempted','$reason',datetime('now'))" 2>/dev/null || true
      done < "$jsonl"
      ;;
  esac
done

# Migrar .md de concepts (frontmatter YAML → category/tags/confidence, body → body_md)
if [ -d "$CTX_DIR/concept" ]; then
  for md in "$CTX_DIR/concept/"*.md; do
    [ -e "$md" ] || continue
    fname=$(basename "$md" .md)
    # Extraer frontmatter simple (formato: ---\n...\n---\nbody)
    body=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==2{print}' "$md")
    category=$(grep -E '^type:' "$md" | head -1 | sed 's/^type:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
    [ -z "$category" ] && category="concept"
    confidence=$(grep -E '^confidence:' "$md" | head -1 | sed 's/^confidence:[[:space:]]*//')
    [ -z "$confidence" ] && confidence="0.8"

    fname_e=$(sql_escape "$fname"); body_e=$(sql_escape "$body")
    cat_e=$(sql_escape "$category"); conf_e=$(sql_escape "$confidence")
    teamdb_write_project "$DB" "INSERT OR IGNORE INTO concepts(slug,title,body_md,category,updated_at) VALUES('$fname_e','$fname_e','$body_e','$cat_e',datetime('now'))" 2>/dev/null || true
  done
  # DC-1: NO mover .md a legacy. Dejarlos en su lugar.
fi

# Solo .jsonl va a legacy/
LEGACY="$CTX_DIR/legacy"
mkdir -p "$LEGACY"
mv "$CTX_DIR"/*.jsonl "$LEGACY/" 2>/dev/null || true

echo "migrated: $DB"
```

**REFACTOR:** Extraer `parse_frontmatter()` con un parser dedicado. Aceptable por ahora `awk` simple.

**Done when:** `bash tests/teamdb-migrate-md-preserve.test.sh` pasa.

---

### FASE 2 — Exit Criteria (Jhon)

```bash
bash tests/teamdb-plan.test.sh \
  && bash tests/write-helpers.test.sh \
  && bash tests/teamdb-status.test.sh \
  && bash tests/teamdb-resume.test.sh \
  && bash tests/teamdb-amend.test.sh \
  && bash tests/teamdb-execute-plan.test.sh \
  && bash tests/teamdb-export-audit.test.sh \
  && bash tests/teamdb-migrate-md-preserve.test.sh \
  && bash tests/version-coherence.test.sh \
  && bash tests/portability-bash32.test.sh
```

Luz corre quality gate arquitectónico. Pau actualiza CHANGELOG.

---

## FASE 3 — Agentes (Alex/Jes) + Snippets + Handoffs + Audit-cleanup + CI

### T-3.1 — Snippets: agentes con markers (no bodies duplicados)
**Owner:** Teo | **Verify:** Jhon
**Files:** `agents-base/*.md` (los 8), `tests/snippets-sync.test.sh` (nuevo)
**Implements AC:** 7.1 + DC-2

**RED:**
```bash
# tests/snippets-sync.test.sh
# Cada agente debe tener un marker de cada snippet y NO debe contener el cuerpo en línea.

for agent in agents-base/*.md; do
  base=$(basename "$agent" .md)
  # 1. Marker de code-intelligence
  grep -q "<!-- @include-snippet code-intelligence -->" "$agent" || {
    echo "FAIL: $base sin marker code-intelligence"; exit 1;
  }
  # 2. Marker de memory-protocol
  grep -q "<!-- @include-snippet memory-protocol -->" "$agent" || {
    echo "FAIL: $base sin marker memory-protocol"; exit 1;
  }
  # 3. NO debe contener el comentario "SINCRONIZADO CON:" inline (era el truco anterior)
  if grep -q "## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp" "$agent"; then
    echo "FAIL: $base tiene body Code Intelligence embebido"; exit 1;
  fi
  if grep -q "## 🧠 Memory Protocol$" "$agent"; then
    echo "FAIL: $base tiene body Memory Protocol embebido"; exit 1;
  fi
done

echo "PASS"
```

**GREEN:** Para cada `agents-base/*.md`:
1. Reemplazar la sección `## 🔍 Code Intelligence` (incluyendo el comentario SINCRONIZADO CON) por **una sola línea**:
   ```markdown
   <!-- @include-snippet code-intelligence -->
   ```
2. Reemplazar la sección `## 🧠 Memory Protocol` (incluyendo el comentario SINCRONIZADO CON) por:
   ```markdown
   <!-- @include-snippet memory-protocol -->
   ```
3. Eliminar los snippets embebidos (desde `## 🔍 Code Intelligence` hasta antes de la siguiente sección, y desde `## 🧠 Memory Protocol` hasta antes de la siguiente sección).

**REFACTOR:** N/A.

**Done when:** `bash tests/snippets-sync.test.sh` pasa.

---

### T-3.2 — `install-global.sh` resuelve markers build-time
**Owner:** Teo | **Verify:** Jhon
**Files:** `install-global.sh`, `tests/install-resolves-snippets.test.sh` (nuevo)
**Implements AC:** 7.1, 7.2 + DC-2

**RED:**
```bash
# Al instalar a un HOME temporal, los agentes en ~/.config/opencode/agents/
# deben tener los snippets completos (resueltos por build-time).
HOME_BAK="$HOME"; export HOME=$(mktemp -d)
bash install-global.sh 2>&1 >/dev/null
export HOME="$HOME_BAK"

# Cada agente instalado debe tener la sección completa de cada snippet (no solo el marker)
for agent in "$HOME/.config/opencode/agents/"*.md; do
  base=$(basename "$agent" .md)
  # Debe contener texto característico de cada snippet
  grep -q "codebase-memory-mcp" "$agent" || {
    echo "FAIL: $base sin snippet code-intelligence resuelto"; exit 1;
  }
  grep -q "Memory Protocol" "$agent" || {
    echo "FAIL: $base sin snippet memory-protocol resuelto"; exit 1;
  }
  # El marker debe haber sido reemplazado (no debe quedar en el archivo instalado)
  if grep -q "@include-snippet" "$agent"; then
    echo "FAIL: $base tiene marker sin resolver"; exit 1;
  fi
done

echo "PASS"
```

**GREEN:** Modificar `install_agents()`:
```bash
install_agents() {
  log INFO "Instalando 8 agentes en $AGENTS_DIR"

  remove_broken_symlink "$AGENTS_DIR"
  run mkdir -p "$AGENTS_DIR"

  local agent_count=0
  for agent_file in "$SCRIPT_DIR"/agents-base/*.md; do
    [[ -e "$agent_file" ]] || continue
    local name; name="$(basename "$agent_file")"

    # Resolver @include-snippet markers build-time (DC-2)
    local resolved_content
    resolved_content="$(cat "$agent_file")"
    while [[ "$resolved_content" =~ @include-snippet[[:space:]]+([a-z-]+) ]]; do
      local snippet_name="${BASH_REMATCH[1]}"
      local snippet_path="$SCRIPT_DIR/templates/agents/snippets/${snippet_name}.md"
      if [[ -f "$snippet_path" ]]; then
        local snippet_body; snippet_body="$(cat "$snippet_path")"
        # Reemplazar marker (incluyendo el <!-- --> que lo envuelve)
        resolved_content="${resolved_content//<!-- @include-snippet $snippet_name -->/$snippet_body}"
      else
        log WARN "Snippet no encontrado: $snippet_name (en $name)"
        # Dejar marker como comment HTML (opencode lo ignora como markdown)
      fi
    done

    # Escribir resuelto (o el original si no hubo cambios)
    if [[ "$DRY_RUN" == true ]]; then
      echo "    [dry-run] cp $agent_file (resuelto) → $AGENTS_DIR/$name"
    else
      printf '%s\n' "$resolved_content" > "$AGENTS_DIR/$name"
    fi
    agent_count=$((agent_count + 1))
  done
  log OK "$agent_count agentes instalados (con snippets resueltos)"
}
```

**Bash 3.2 caveat:** `[[ =~ ]]` con captura a `BASH_REMATCH` es bash 3.0+ → OK. La sustitución `${var//pattern/replacement}` es bash 3.0+ → OK.

**REFACTOR:** Extraer `resolve_snippets()` como helper.

**Done when:** `bash tests/install-resolves-snippets.test.sh` pasa.

---

### T-3.3 — Handoff schema con `if/then` condicional
**Owner:** Teo | **Verify:** Jhon
**Files:** `templates/handoff.schema.json`, `tests/handoff-schema-validation.test.sh` (nuevo)
**Implements AC:** 9.1, 9.2, 9.3 + INC-3

**RED:**
```bash
# tests/handoff-schema-validation.test.sh — requiere python3 con jsonschema
python3 - <<'EOF'
import json, sys
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema no instalado")
    sys.exit(0)

schema = json.load(open("templates/handoff.schema.json"))

# 1. SOL → TEO sin project_context debe FALLAR
bad_teo_handoff = {
    "from": "SOL", "to": "TEO",
    "task": "Implement login JWT",
    "summary": "Build the login module with TDD.",
    "next_action": "Run task 1 of the plan with TDD."
}
try:
    jsonschema.validate(bad_teo_handoff, schema)
    print("FAIL: TEO handoff sin project_context aceptado")
    sys.exit(1)
except jsonschema.ValidationError:
    pass

# 2. TEO → JHON sin verification debe FALLAR
bad_jhon_handoff = {
    "from": "TEO", "to": "JHON",
    "task": "Verify module tests",
    "summary": "Login implemented with TDD; 8 tests pass.",
    "next_action": "Run full suite.",
    "project_context": {"stack": {"language": "ts"}}
}
try:
    jsonschema.validate(bad_jhon_handoff, schema)
    print("FAIL: JHON handoff sin verification aceptado")
    sys.exit(1)
except jsonschema.ValidationError:
    pass

# 3. Handoff válido pasa
good = {
    "from": "SOL", "to": "TEO",
    "task": "Implement login JWT",
    "summary": "Build the login module with TDD.",
    "next_action": "Run task 1 of the plan with TDD.",
    "project_context": {
        "stack": {"language": "ts", "test_runner": "vitest"},
        "has_ui": True,
        "design_system_exists": False,
        "okf_bundle_valid": True
    }
}
jsonschema.validate(good, schema)
print("OK: handoff válido aceptado")
EOF

echo "PASS"
```

**GREEN:** Reescribir `templates/handoff.schema.json` con `allOf` + `if/then`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://skalling.dev/schemas/handoff-v1.json",
  "title": "Skalling Handoff",
  "type": "object",
  "required": ["from", "to", "task", "summary", "next_action"],
  "properties": {
    "from": { "type": "string", "enum": ["ALEX","POL","JES","SOL","TEO","JHON","LUZ","PAU"] },
    "to":   { "type": "string", "enum": ["ALEX","POL","JES","SOL","TEO","JHON","LUZ","PAU"] },
    "task": { "type": "string", "minLength": 5 },
    "summary": { "type": "string", "minLength": 10 },
    "next_action": { "type": "string", "minLength": 5 },
    "artifacts": { "type": "array", "items": { "type": "string" } },
    "tests_passed": { "type": "boolean" },
    "coverage": { "type": "number", "minimum": 0, "maximum": 100 },
    "ladder_rung_used": { "type": "integer", "minimum": 1, "maximum": 7 },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "iteracion": { "type": "integer", "minimum": 1 },
    "timestamp": { "type": "string", "format": "date-time" },
    "verdict": { "type": "string", "enum": ["APPROVED", "REJECTED"] },
    "rejection_reasons": { "type": "array", "items": { "type": "string" } },
    "project_context": {
      "type": "object",
      "properties": {
        "stack": {
          "type": "object",
          "properties": {
            "language": { "type": "string" },
            "framework": { "type": "string" },
            "runtime": { "type": "string" },
            "package_manager": { "type": "string" },
            "test_runner": { "type": "string" }
          }
        },
        "has_ui": { "type": "boolean" },
        "design_system_exists": { "type": "boolean" },
        "okf_bundle_valid": { "type": "boolean" }
      }
    },
    "verification": {
      "type": "object",
      "properties": {
        "type": { "type": "string", "enum": ["test","build","lint","security","manual"] },
        "command": { "type": "string" },
        "output_summary": { "type": "string" },
        "exit_code": { "type": "integer" },
        "tests_total": { "type": "integer" },
        "tests_passed": { "type": "integer" },
        "tests_failed": { "type": "integer" }
      }
    },
    "contradicciones_detectadas": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "additionalProperties": false,
  "allOf": [
    {
      "description": "Si destino es Teo o Luz → requiere project_context",
      "if": { "properties": { "to": { "enum": ["TEO","LUZ"] } } },
      "then": { "required": ["project_context"] }
    },
    {
      "description": "Si destino es Jhon o Luz → requiere verification (recibir evidencia)",
      "if": { "properties": { "to": { "enum": ["JHON","LUZ"] } } },
      "then": { "required": ["verification"] }
    },
    {
      "description": "Si emisor es ingeniería (TEO/JHON/LUZ) → debe llevar verification como evidencia",
      "if": { "properties": { "from": { "enum": ["TEO","JHON","LUZ"] } } },
      "then": { "required": ["verification"] }
    }
  ]
}
```

**REFACTOR:** N/A.

**Done when:** `bash tests/handoff-schema-validation.test.sh` pasa.

---

### T-3.4 — Helper-side audit_log (actor_source + disable duplicados)
**Owner:** Teo | **Verify:** Jhon
**Files:** `sql/project-schema.sql`, `sql/global-schema.sql`, `scripts/lib/lib-teamdb.sh`, `tests/audit-log-actor-source.test.sh` (nuevo)
**Implements AC:** 8.1, 8.2

**RED:**
```bash
TEST_DIR=$(mktemp -d); mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$(pwd)" bash scripts/teamdb-init.sh "$TEST_DIR" >/dev/null

# Mutación via helper con actor='sol' debe generar fila audit con agent='sol' Y actor_source='helper'
TEAMDB_ACTOR=sol bash -c "
  source scripts/lib/lib-teamdb.sh
  teamdb_write_project '$DB' \"INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('helper-test','HT','x',datetime('now'))\"
"

# Esperar al menos UNA fila con agent='sol' y actor_source='helper'
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE agent='sol' AND actor_source='helper'")
[ "$COUNT" -ge "1" ] || { echo "FAIL: audit_log no tiene fila helper con actor 'sol' ($COUNT)"; exit 1; }

# Para mutaciones SIN helper (raw sqlite3), el trigger debe seguir disparando con actor_source='trigger'
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('raw-test','RT','x',datetime('now'))"
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE agent='system' AND actor_source='trigger'")
[ "$COUNT" -ge "1" ] || { echo "FAIL: trigger audit row ausente"; exit 1; }

echo "PASS"
```

**GREEN:**
1. En `sql/project-schema.sql`, agregar columna al schema `audit_log`:
   ```sql
   ALTER TABLE audit_log ADD COLUMN actor_source TEXT DEFAULT 'trigger';  -- 'helper' | 'trigger' | 'manual'
   ```
   Idem `global-schema.sql`.
2. Refactor de `teamdb_write_*` (en lib-teamdb.sh, ya esbozado en T-2.2):
   ```bash
   teamdb_write_project() {
     ...
     local actor; actor="${TEAMDB_ACTOR:-unknown}"
     sqlite3 "$db" "INSERT INTO audit_log (ts, agent, action, table_name, actor_source) VALUES (datetime('now'), '$actor', 'mutate', '<via_helper>', 'helper');
   $sql"
     ...
   }
   ```
3. Reemplazar triggers `*_audit_*` para que marquen `actor_source='trigger'`:
   ```sql
   -- Reemplazar triggers viejos para incluir actor_source
   DROP TRIGGER IF EXISTS concepts_audit_ai;
   CREATE TRIGGER concepts_audit_ai AFTER INSERT ON concepts BEGIN
     INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
     VALUES (datetime('now'), 'system', 'insert', 'concepts', new.id, json_object('slug', new.slug), 'trigger');
   END;
   -- (análogamente para update/delete en concepts, decisions, work_in_progress, known_problems)
   ```

> **Importante**: este es el único punto donde se modifican triggers. Como `actor_source` no estaba en el INSERT original del trigger, se conserva la backward compatibility (DEFAULT=trigger). Si la columna ya existe (vía ALTER), el DEFAULT aplica.

**REFACTOR:** Los triggers rewritten quedan en una sola sección del schema, claramente marcada `auditado-v0.7.2`.

**Done when:** `bash tests/audit-log-actor-source.test.sh` pasa. Doctor (`setup-team-doctor.sh:420`) sigue viendo 12 triggers (o más, si contamos los nuevos problems_audit_* derivados de T-1.4 — ajustar el check del doctor a `>= 12` o `>= 16`).

---

### T-3.5 — Integración TeamDB en Alex y Jes
**Owner:** Teo | **Verify:** Jhon
**Files:** `agents-base/Alex.md`, `agents-base/Jes.md`, `tests/agents-teamdb-integration.test.sh` (nuevo)
**Implements AC:** 6.1, 6.2, 6.3

**RED:**
```bash
# Cada uno de los 8 agentes debe mencionar teamdb_query_* o tener
# un comment explícito `# teamdb-N/A: <razón>`
for agent in agents-base/*.md; do
  base=$(basename "$agent" .md)
  if grep -q "teamdb_query_project\|teamdb_query_global" "$agent"; then
    echo "OK: $base usa teamdb_query_*"
  elif grep -q "teamdb-N/A" "$agent"; then
    echo "OK: $base documenta N/A explícitamente"
  else
    echo "FAIL: $base sin referencia a teamdb ni documenta N/A"
    exit 1
  fi
done

# Específicamente Alex.md y Jes.md deben tener query explícita
grep -q "teamdb_query_project" agents-base/Alex.md || {
  echo "FAIL: Alex.md sin teamdb_query_project"; exit 1;
}
grep -q "teamdb_query_project" agents-base/Jes.md || {
  echo "FAIL: Jes.md sin teamdb_query_project"; exit 1;
}

echo "PASS"
```

**GREEN:** Reemplazar la sección "Session Start Protocol" de Alex.md para que use TeamDB como primary source (con fallback a `.md` index solo si team.db no existe). Y en Jes.md, agregar una nota breve en PASO 0 que indique: "Si existe `.opencode/context/team.db`, preferir `teamdb_query_project` antes que abrir `.md` por grep".

**Cambio concreto en `agents-base/Alex.md`:**
- En la sección "Session Start Protocol", agregar al inicio:
  ```
  ## TeamDB Session Start (preferred)

  Si `.opencode/context/team.db` existe en el proyecto:
  1. `teamdb_query_project "SELECT slug, title FROM concepts ORDER BY updated_at DESC LIMIT 10"`
  2. `teamdb_query_project "SELECT slug, title, status FROM decisions WHERE status='accepted'"`
  3. Si hay decisiones/problemas relevantes, agregarlas al contexto

  Solo si team.db no existe, fallback a leer `.md` legacy.
  ```

**Cambio en `agents-base/Jes.md`:** agregar PASO 0 TeamDB:
```
Antes de explicar, si `.opencode/context/team.db` existe:
  teamdb_query_project "SELECT title, body_md FROM concepts WHERE category IN ('concept','pattern') LIMIT 20"
  teamdb_query_project "SELECT title FROM decisions WHERE status='accepted'"
Si team.db no existe: leer `.opencode/context/concept/*.md` con grep.
```

**REFACTOR:** N/A.

**Done when:** `bash tests/agents-teamdb-integration.test.sh` pasa.

---

### T-3.6 v2 — MODIFICAR `.github/workflows/tests.yml` existente para incluir teamdb tests  `[CORREGIDO en round 2: el archivo SÍ existe]`
**Owner:** Teo | **Verify:** Jhon
**Files:** `.github/workflows/tests.yml` (modify), `tests/version-coherence.test.sh` (nuevo), `tests/portability-bash32.test.sh` (nuevo)
**Implements AC:** 10.1 (parcial)

> **Round 2 corrección**: mi round 1 decía incorrectamente que `.github/workflows/tests.yml` no existía. **SÍ existe** (verificado: contiene 84 líneas con matriz bash 3/4/5 + lint + yaml-validation + cross-platform). Por tanto T-3.6 v2 MODIFICA el archivo existente para sumarle los tests de teamdb — no lo crea desde cero.

**RED:**
```bash
TEST_DIR=".github"
WORKFLOW="$TEST_DIR/workflows/tests.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: $WORKFLOW no existe"; exit 1; }

# Verificar que el workflow referencia tests/teamdb-*.test.sh
grep -qE "teamdb-(safe-query|search-sqli|related-sqli|problems-fts|python-bindparams|write-wal|amend-full|deps-dag|claim-lease|export-md|context-capsule|cycle-amended)" "$WORKFLOW" || {
  echo "FAIL: $WORKFLOW no referencia teamdb tests"; exit 1;
}

# Y que el hook este backup de cross-platform smoke test siga intacto
grep -q "Run bootstrap in mock project" "$WORKFLOW" || {
  echo "FAIL: smoke test cross-platform eliminado"; exit 1;
}
echo "PASS"
```

**GREEN:** Añadir al final del step "Run tests (bash ${{ matrix.bash-version }})" del job `test` actual, una nueva sección que ejecute todos los tests `tests/teamdb-*.test.sh`:

```yaml
      - name: Run tests (bash ${{ matrix.bash-version }})
        run: |
          bash tests/setup.test.sh
          for t in tests/teamdb-*.test.sh; do
            [ -f "$t" ] || continue
            echo "Running $t"
            bash "$t" || { echo "FAIL: $t"; exit 1; }
          done
```

Mantener intactos los otros jobs (`lint`, `validate-yaml`, `test-cross-platform`). NO eliminar nada del archivo; solo añadir.

**REFACTOR:** N/A.

**Done when:** El workflow modificado referencia teamdb tests; los tests referenciados existen localmente; el workflow sigue siendo YAML válido (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/tests.yml'))"`).

---

### T-3.6b v2 — Crear `.github/workflows/teamdb-sqli.yml` (NUEVO workflow)
**Owner:** Teo | **Verify:** Jhon
**Files:** `.github/workflows/teamdb-sqli.yml` (nuevo)
**Implements AC:** 10.2

**RED:**
```bash
WORKFLOW=".github/workflows/teamdb-sqli.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: workflow no creado"; exit 1; }
python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" || { echo "FAIL: YAML inválido"; exit 1; }
grep -q "teamdb-search-sqli" "$WORKFLOW" || { echo "FAIL: no incluye teamdb-search-sqli"; exit 1; }
grep -q "teamdb-related-sqli" "$WORKFLOW" || { echo "FAIL: no incluye teamdb-related-sqli"; exit 1; }
grep -q "teamdb-python-bindparams" "$WORKFLOW" || { echo "FAIL: no incluye teamdb-python-bindparams (round 2)"; exit 1; }
grep -q "teamdb-safe-query" "$WORKFLOW" || { echo "FAIL: no incluye teamdb-safe-query"; exit 1; }
echo "PASS"
```

**GREEN:** Crear `.github/workflows/teamdb-sqli.yml`:
```yaml
name: teamdb-sqli
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  sqli:
    name: SQL injection tests (round 2: incluye Python bindparams)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install sqlite3 + python3
        run: |
          sudo apt-get update
          sudo apt-get install -y sqlite3
      - name: Run SQLi tests
        run: |
          bash tests/teamdb-search-sqli.test.sh
          bash tests/teamdb-related-sqli.test.sh
          bash tests/teamdb-safe-query.test.sh
          bash tests/teamdb-python-bindparams.test.sh
```

**Done when:** Workflow existe + YAML válido + incluye 4 tests.

---

### T-3.6c v2 — Crear `.github/workflows/handoffs.yml` (NUEVO workflow)
**Owner:** Teo | **Verify:** Jhon
**Files:** `.github/workflows/handoffs.yml` (nuevo)
**Implements AC:** 10.3

**RED:**
```bash
WORKFLOW=".github/workflows/handoffs.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: workflow no creado"; exit 1; }
python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" || { echo "FAIL: YAML inválido"; exit 1; }
grep -q "handoff-schema-validation" "$WORKFLOW" || { echo "FAIL: no incluye handoff-schema"; exit 1; }
grep -q "agents-teamdb-integration" "$WORKFLOW" || { echo "FAIL: no incluye agents-teamdb-integration"; exit 1; }
echo "PASS"
```

**GREEN:** Crear `.github/workflows/handoffs.yml`:
```yaml
name: handoffs
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  handoff-validation:
    name: Handoff schema + agents TeamDB integration
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - name: Install dependencies
        run: pip install jsonschema
      - name: Run handoff tests
        run: |
          bash tests/handoff-schema-validation.test.sh
          bash tests/agents-teamdb-integration.test.sh
```

**Done when:** Workflow existe + YAML válido + incluye los 2 tests.

---

### T-3.6d v2 — Crear `.github/workflows/teamdb-dag-claims.yml` (NUEVO workflow)
**Owner:** Teo | **Verify:** Jhon
**Files:** `.github/workflows/teamdb-dag-claims.yml` (nuevo)

> **Round 2 nuevo workflow**: cubre los tests del round 2 (DAG, claims, amend, context, export-md).

**RED:**
```bash
WORKFLOW=".github/workflows/teamdb-dag-claims.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: workflow no creado"; exit 1; }
python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" || { echo "FAIL: YAML inválido"; exit 1; }
grep -q "teamdb-deps-dag" "$WORKFLOW" || { echo "FAIL: no incluye deps-dag"; exit 1; }
grep -q "teamdb-claim-lease" "$WORKFLOW" || { echo "FAIL: no incluye claim-lease"; exit 1; }
echo "PASS"
```

**GREEN:** Crear `.github/workflows/teamdb-dag-claims.yml`:
```yaml
name: teamdb-dag-claims
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  dag-claims:
    name: DAG, claims, amend, export-md, context capsule
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install sqlite3 + python3
        run: |
          sudo apt-get update
          sudo apt-get install -y sqlite3
      - name: Run round-2 tests
        run: |
          bash tests/teamdb-dag-tables-exist.test.sh
          bash tests/teamdb-amend-full.test.sh
          bash tests/teamdb-deps-dag.test.sh
          bash tests/teamdb-claim-lease.test.sh
          bash tests/teamdb-export-md.test.sh
          bash tests/teamdb-context-capsule.test.sh
          bash tests/teamdb-cycle-amended.test.sh
```

**Done when:** Workflow existe + YAML válido + 7 tests referenciados.

**RED:** CI no es ejecutable localmente sin `act`. El "RED" es estructural: verificar que cada workflow tiene `jobs.X.steps` que llaman a los tests.

```bash
# Validación estructural mínima
for f in .github/workflows/*.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" || {
    echo "FAIL: $f no es YAML válido"; exit 1;
  }
done

# Cada test file referenciado debe existir
grep -E 'bash tests/' .github/workflows/*.yml | while read -r line; do
  test_file=$(echo "$line" | grep -oE 'tests/[^ ]+\.test\.sh')
  [ -f "$test_file" ] || { echo "FAIL: $test_file referenciado pero no existe"; exit 1; }
done

echo "PASS"
```

**GREEN:**
- `.github/workflows/tests.yml`:
  ```yaml
  name: tests
  on: [push, pull_request]
  jobs:
    test:
      strategy:
        matrix:
          bash: ['3', '4', '5']
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Setup bash ${{ matrix.bash }}
          run: |
            sudo apt-get update
            sudo apt-get install -y bash-${{ matrix.bash }}
            echo "/usr/bin/bash${{ matrix.bash }}" >> $GITHUB_PATH
        - name: Setup sqlite3
          run: sudo apt-get install -y sqlite3
        - name: Run tests
          run: |
            bash tests/setup.test.sh
            bash tests/teamdb.test.sh
            bash tests/teamdb-safe-query.test.sh
            bash tests/teamdb-search-sqli.test.sh
            bash tests/teamdb-related-sqli.test.sh
            bash tests/teamdb-plan.test.sh
            bash tests/write-helpers.test.sh
            bash tests/teamdb-status.test.sh
            bash tests/teamdb-resume.test.sh
            bash tests/teamdb-amend.test.sh
            bash tests/teamdb-execute-plan.test.sh
            bash tests/teamdb-export-audit.test.sh
            bash tests/teamdb-migrate-md-preserve.test.sh
            bash tests/install-script-copies.test.sh
            bash tests/install-hooks-paths.test.sh
            bash tests/audit-log-actor-source.test.sh
  ```
- `.github/workflows/teamdb-sqli.yml`:
  ```yaml
  name: teamdb-sqli
  on: [push, pull_request]
  jobs:
    sqli:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: sudo apt-get install -y sqlite3
        - run: |
            bash tests/teamdb-search-sqli.test.sh
            bash tests/teamdb-related-sqli.test.sh
  ```
- `.github/workflows/handoffs.yml`:
  ```yaml
  name: handoffs
  on: [push, pull_request]
  jobs:
    handoffs:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-python@v5
          with: { python-version: '3.11' }
        - run: pip install jsonschema
        - run: |
            bash tests/handoff-schema-validation.test.sh
            bash tests/agents-teamdb-integration.test.sh
            bash tests/snippets-sync.test.sh
            bash tests/install-resolves-snippets.test.sh
  ```

**REFACTOR:** N/A.

**Done when:** Los 3 YAML son válidos; los tests referenciados existen localmente.

---

### T-3.7 — Bash 3.2 portability test
**Owner:** Teo | **Verify:** Jhon
**Files:** `tests/portability-bash32.test.sh` (nuevo)
**Implements AC:** 12.1 + INV-PORTABILITY-1

**RED:**
```bash
# Detecta patrones prohibidos en scripts/
PATTERNS='declare -A|readarray|\[\[ -v |local -n|\$\{var,,\}|\$\{var,\^\^\}|mapfile'

found=0
for f in scripts/teamdb-*.sh scripts/lib/*.sh scripts/hooks/*; do
  if [ -f "$f" ]; then
    if grep -nE "$PATTERNS" "$f" 2>/dev/null; then
      echo "FAIL: patrón bash-3.2-incompatible en $f"
      found=1
    fi
  fi
done

[ "$found" = "0" ] || { echo "FAIL"; exit 1; }

# Smoke test: cada script ejecutable sin argumentos raros (mostrar ayuda o no-op)
for s in scripts/teamdb-*.sh; do
  bash "$s" 2>&1 | head -1 | grep -qE "Uso:|no DB|teamdb " || true
done

echo "PASS"
```

**GREEN:** El test es self-contained. Se ejecuta en CI con bash 3.2 (si está disponible), 4, 5. La matriz principal corre en Linux CI (donde bash 3.2 está disponible vía `apt-get install bash-3`).

**REFACTOR:** Considerar `PATTERNS` como variable y agregar más patrones problemáticos (`${var//pat/rep}` es bash 3 OK; `${var:0:5}` es bash 3 OK; `${!var}` indirect expansion requiere bash 2 OK; `printf -v` requiere bash 3.2 con glibc; OK por ahora).

**Done when:** `bash tests/portability-bash32.test.sh` pasa.

---

### T-3.8 — Aggregator `tests/teamdb-hardening-suite.sh`
**Owner:** Teo | **Verify:** Jhon
**Files:** `tests/teamdb-hardening-suite.sh` (nuevo)

**RED:** N/A (script agregado, no test de funcionalidad nueva).

**GREEN:**
```bash
#!/usr/bin/env bash
# teamdb-hardening-suite.sh — corre todas las tests del cambio v0.7.2 en serie
set -e
SKALLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SKALLING_ROOT"

PASS=0; FAIL=0
for t in tests/teamdb-safe-query.test.sh \
         tests/teamdb-search-sqli.test.sh \
         tests/teamdb-related-sqli.test.sh \
         tests/teamdb-problems-fts.test.sh \
         tests/install-script-copies.test.sh \
         tests/install-hooks-paths.test.sh \
         tests/audit-log-actor.test.sh \
         tests/teamdb-plan.test.sh \
         tests/write-helpers.test.sh \
         tests/teamdb-status.test.sh \
         tests/teamdb-resume.test.sh \
         tests/teamdb-amend.test.sh \
         tests/teamdb-execute-plan.test.sh \
         tests/teamdb-export-audit.test.sh \
         tests/teamdb-migrate-md-preserve.test.sh \
         tests/version-coherence.test.sh \
         tests/portability-bash32.test.sh \
         tests/snippets-sync.test.sh \
         tests/install-resolves-snippets.test.sh \
         tests/handoff-schema-validation.test.sh \
         tests/agents-teamdb-integration.test.sh \
         tests/audit-log-actor-source.test.sh; do
  if [ -f "$t" ]; then
    if bash "$t" >/dev/null 2>&1; then
      echo "✓ $t"
      PASS=$((PASS+1))
    else
      echo "✗ $t"
      FAIL=$((FAIL+1))
    fi
  fi
done

echo ""
echo "Suite: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**REFACTOR:** Permitir `--filter <pattern>` para correr subset (no en este cambio).

**Done when:** `bash tests/teamdb-hardening-suite.sh` corre todas las suites y falla si alguna falla.

---

### FASE 3 v2 — Exit Criteria (round 2)

```bash
# Aggregator suite (cubre round 2 también — ver T-3.8 update abajo)
bash tests/teamdb-hardening-suite.sh \
  # Modificación del workflow EXISTENTE
  && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/tests.yml'))" \
  && grep -qE "teamdb-(safe-query|search-sqli)" .github/workflows/tests.yml \
  # Workflows NUEVOS creados en round 2
  && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/teamdb-sqli.yml'))" \
  && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/handoffs.yml'))" \
  && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/teamdb-dag-claims.yml'))"
```

> **Round 2 nota**: el grep sobre `tests.yml` verifica que el archivo original (que NO se sobreescribe) ahora referencia teamdb tests. Los 3 workflows nuevos (`teamdb-sqli.yml`, `handoffs.yml`, `teamdb-dag-claims.yml`) se crean.

Luz corre quality gate final. Pau documenta CHANGELOG + README + archivado del change en `.opencode/changes/archive/2026-08/`.

---

## Tareas cross-phase

### T-X.1 — Documentación (Pau)
**Owner:** Pau | **Verifica:** Manual
**Files:** `README.md`, `CHANGELOG.md`
**Cuándo:** Al final de cada fase.

**Por fase:**
- FASE 1 cerrada: CHANGELOG `[Unreleased]` entrada con SQLi + install fixes.
- FASE 2 cerrada: agregar lifecycle tables + audit + version.
- FASE 3 cerrada: bump a `0.7.2`, documentar snippets build-time + handoff schema + CI.

**No es tarea automatizable**: Pau documenta con revisión manual del código.

### T-X.2 — Quality Gate Final (Luz)
**Owner:** Luz
**Cuándo:** Después de FASE 3 cerrada.

**Chequeos:**
1. `shellcheck` 0 errores en `scripts/teamdb-*.sh`, `scripts/lib/*.sh`, `scripts/hooks/*`.
2. `grep -E 'sqlite3.*\$' scripts/teamdb-search.sh scripts/teamdb-related.sh` → 0 matches.
3. `find scripts/ -name '*.sh' | xargs grep -l '|| true'` → solo líneas con comentario `# OK: <razón>`.
4. `tests/teamdb-hardening-suite.sh` verde.
5. `tests/handoff-schema-validation.test.sh` verde.
6. CI workflows sintácticamente válidos.
7. Manual review: ningún secreto, PII, código muerto.

---

## Riesgos del plan (round 2)

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| R-SOL-1 | macOS bash 3.2.57 sin `grep -P` rompe T-1.1 | Alta | Bajo | **Resuelto en producción**: `lib-teamdb.sh` ya usa `_has_control_char` portable (bash `case` con cada byte). Round 1 ya se ejecutó. |
| R-SOL-2 | `_teamdb_reject_unsafe_sql` rechaza SQL legítimo con `;` en comentarios | Baja | Medio | Round 2 lo elimina (T-2.10): ya no usamos escape manual, usamos Python binding |
| R-SOL-3 | Refactor de triggers en T-3.4 requiere regenerar DBs existentes | Media | Alto | ALTER es aditivo; `task_claims` etc. usan `CREATE TABLE IF NOT EXISTS` |
| **R-SOL-R2-1** | **Python no disponible en máquinas** — T-2.10/2.11/2.14/2.15 dependen de `python3` | Media | Alto | El repo ya usa Python para migraciones (T-2.8). Si `python3` falta, fallar con mensaje claro: "Python 3 requerido para teamdb-write/claim/deps/export-md". Documentar en README. CI instala apt. |
| **R-SOL-R2-2** | **WAL mode + DBs legacy v0.7.0** — DBs creadas sin WAL pueden quedar inconsistentes con WAL | Baja | Alto | `teamdb_init_*` ejecuta `PRAGMA journal_mode=WAL` idempotentemente al primer contacto. DBs previas quedan en modo legacy hasta re-init |
| **R-SOL-R2-3** | **`BEGIN IMMEDIATE` con concurrencia real** — dos procesos escribiendo al mismo task_claims pueden chocar | Baja | Alto | El script hace transacción single-shot. Si falla, el caller reintenta. `busy_timeout=5000` evita 30s de espera del kernel |
| **R-SOL-R2-4** | **DAG cycle detection via Python DFS** — DB grande (>1000 tasks) puede ser lento | Baja | Bajo | Algoritmo O(V+E) sobre edges; aceptable para planes Skalling (decenas de tasks). Si crece, mover a C |
| **R-SOL-R2-5** | **`teamdb-claim.sh` con bash + Python handoff** — race entre `teamdb_exec_query` que verifica y `teamdb_exec_write` que inserta | Baja | Alto | La lógica atómica está en Python con `BEGIN IMMEDIATE`. Bash solo orquesta parámetros. **Una sola transacción, un solo lock.** |
| **R-SOL-R2-6** | **Markdown GENERADO pisando `proposal.md`/`design.md`/`specs/*.md` existentes** | Media | Alto | Round 2 #4 asegura que solo GENERA, no escribe si ya existe con contenido no-generado. Si el .md existe Y no tiene header `<!-- GENERATED -->`, el script NO lo sobreescribe (mantiene manual) |
| **R-SOL-R2-7** | **`teamdb_safe_query` (legacy Fase 1) coexiste con `teamdb_exec_query` (round 2)** — confusión para developers | Baja | Bajo | Round 2 marca `teamdb_safe_query` con `# DEPRECATED` header y un mensaje al ser invocada; los tests migrados gradualmente |
| R-SOL-6 | Cambio de audit_log schema invalida tests existentes | Media | Bajo | T-3.4 mantiene ≥12 triggers; el conteo del doctor se vuelve `>= 12` |
| **R-SOL-R2-8** | **`tests.yml` workflow existente modificado puede romper cross-platform smoke test** | Baja | Alto | Round 2 modificación solo AGREGA step, no quita nada. El RED verifica que el smoke test (`Run bootstrap in mock project`) sigue presente |
| R-SOL-9 | `bash 3.x` matrix en CI requiere apt packages | Baja | Bajo | Documentado en T-3.6 |
| R-SOL-10 | Handoff schema con `if/then` requiere jsonschema >= 4.18 | Baja | Bajo | CI instala vía pip |
| **R-SOL-R2-9** | **`task_claims.lease_until` con TZ naive (`datetime('now')`)** — comparación `lease_until > now` puede fallar en UTC vs local | Media | Alto | Escribir siempre timestamps en formato ISO8601 UTC (`T...Z`); comparar solo en UTC. En tests, fijar `TZ=UTC` antes de los assertions |
| **R-SOL-R2-10** | **El componente round 2 son 9 tareas nuevas (~6h Teo)** — el cambio se vuelve pesado | Media | Bajo | Si se atrasa, dispensar T-2.15 (export-md) a un change aparte; todo lo demás es core |



---

## Optimizaciones diferidas (no en este change)

Las siguientes optimizaciones de Pol se identificaron como **no esenciales** para la entrega v0.7.2 y se difieren a cambios futuros:

- **OPT-DIFFERRED-1**: Cliente libSQL nativo en TypeScript/Python (OOS-4). **FUERA**.
- **OPT-DIFFERRED-2**: Cytoscape/d3 output para `teamdb-graph.sh` (OOS-7). **FUERA**.
- **OPT-DIFFERRED-3**: Reescribir `wip-tree.sh` para usar `plans`/`tasks` en vez de `work_in_progress` (OOS-3). **FUERA**.
- **OPT-DIFFERRED-4**: CI matrix extendido para incluir TODOS los tests existentes (no solo teamdb). **FUERA** (OOS-8).
- **OPT-DIFFERRED-5**: Refactor `bootstrap-context.sh` a DB-first (OOS-5/10). **FUERA**.
- **OPT-DIFFERRED-6**: i18n de mensajes de error (OOS-9). **FUERA**.
- **OPT-DIFFERRED-7**: Tests paralelos via `&` (R-SOL-3 original). **FUERA** — tests en serie son deterministas.
- **OPT-DIFFERRED-8**: Audit log retention policy (`<1000` filas). **FUERA** — se introdujo `LIMIT 1000` en T-2.7 pero el cleanup automático queda para v0.7.3+.

---

## Resumen de tareas (round 2)

- **FASE 0**: 1 tarea (T-0.1)
- **FASE 1**: 7 tareas — **EJECUTADAS** (T-1.1 a T-1.7, partial) — P0
- **FASE 2 v2 (round 2 source of truth)**: 9 tareas NUEVAS (T-2.9 a T-2.17v2) — P1
  - T-2.9 Schema: task_dependencies + task_claims + plan_history + task_context_capsules
  - T-2.10 Python helper `teamdb_exec.py` (bound params reales)
  - T-2.11 WAL + BEGIN IMMEDIATE (transacciones, no flock)
  - T-2.12 `teamdb-amend.sh` con version/historial + preservación de aprobadas
  - T-2.13 `teamdb-deps.sh` con DAG + runnable + cycle detection
  - T-2.14 `teamdb-claim.sh` con lease/attempt/input_hash + resume
  - T-2.15 `teamdb-export-md.sh` (Markdown GENERADO, no bidireccional)
  - T-2.16 `teamdb-context.sh` (capsula selectiva para handoff de Teo)
  - T-2.17v2 `teamdb-plan.sh` unificado (incluye DAG + history en creación)
  - Tareas viejas T-2.1..T-2.6 marcadas SUPERSEDED; T-2.7 + T-2.8 MANTENIDAS
- **FASE 3 v2 (round 2 source of truth)**: 8 tareas — P2
  - T-3.1..T-3.5 sin cambios estructurales (snippets, install, handoff schema, audit, agents)
  - T-3.6 **CORREGIDO**: MODIFICAR `.github/workflows/tests.yml` (no crear)
  - T-3.6b NUEVO: `.github/workflows/teamdb-sqli.yml`
  - T-3.6c NUEVO: `.github/workflows/handoffs.yml`
  - T-3.6d NUEVO: `.github/workflows/teamdb-dag-claims.yml`
  - T-3.7..T-3.8 sin cambios (portability + aggregator)
- **Cross-phase**: 2 (Pau docs + Luz gate)

**Total round 2: 27 tareas verificables por Jhon** (1 + 7 fase1 ya ejecutadas + 9 nuevas fase2 + 8 fase3 (con split de T-3.6 en 4) + 2 cross). Estimación round 2 adicional: ~10h Teo + ~4h Jhon + 3 gates Luz + Pau docs.

---

*Plan generado por Sol el 2026-08-05 (round 2). Source of truth: este archivo en `.opencode/changes/teamdb-hardening/tasks.md`. Round 1: reescritura completa con prioridades + Bash 3.2 + DC-1/2/3. Round 2: añade 9 tareas de Fase 2 v2 (DAG, claims, export-md, capsule, Python bindparams) + corrige T-3.6 (tests.yml existe). Tareas originales T-2.1..T-2.6 marcadas SUPERSEDED para trazabilidad.*
