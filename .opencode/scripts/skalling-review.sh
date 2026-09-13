#!/usr/bin/env bash
# skalling-review.sh — Revisión estructurada con 4 lenses (bash/sqlite)
# v0.8.3: reemplaza la revisión visual por un análisis de patrones sobre el diff.
#   risk         → eval/rm -rf/curl -k/http:///secretos/chmod 777/SQL injection
#   resilience   → set -euo pipefail, mktemp sin trap, locks sin timeout
#   readability  → funciones largas, vars genéricas, TODO/FIXME/HACK, líneas largas
#   reliability  → scripts sin test que los cubra, tests sin asserts
# Modo --deep: congela el diff en .opencode/context/review/<tree_hash>/ y genera
#   un prompt por lens (risk→Luz, resilience→Jhon, readability→Pau, reliability→Jhon)
#   para que el orchestrator delegue a subagentes. El script NO lanza subagentes.
# Modo --collect <dir>: incorpora findings-<lens>.json producidos por agentes
#   (BLOCKER → exit 1) y sella el receipt de la revisión con el tree_hash del bundle.
# Modo --scope/--exclude: CI gate del linter SQLi. Construye un diff sintético con
#   todas las líneas marcadas como added para los archivos que matchean el glob,
#   excepto los listados en --exclude. Pensado para correr en .github/workflows/
#   lint-sqli.yml sobre scripts/** sin tener que preparar un diff staged.
# Kill switch: SKALLING_REVIEW_MODE=off desactiva (default: on).
#
# ─── Excepciones del linter SQLi (pat_sqli + pat_sqli_dq) ──────────────────────
# El linter detecta interpolación de variables en queries `sqlite3 ... "$VAR"` /
# `sqlite3 ... '$VAR'` (riesgo de SQL injection si $VAR contiene caracteres de
# control). Estos archivos son EXCEPCIONES documentadas — los patrones matchean
# por diseño, no por bug:
#   - scripts/lib/lib-teamdb.sh  → provee helpers seguros (_sql_quote,
#                                 teamdb_exec_value con real parameter binding).
#                                 El linter vería las firmas y los usos internos.
#   - scripts/skalling-review.sh → define pat_sqli/pat_sqli_dq como literales
#                                 regex (líneas ~447-453). Los '$' que matchea
#                                 son parte de la definición del patrón.
#   - scripts/teamdb_exec.py     → wrapper Python con sqlite3 bind params (R10).
#                                 Matchea por las definiciones de patrones
#                                 DML_DANGEROUS/DDL_BENIGN_PREFIXES.
#   - tests/**                   → fixtures con payloads SQLi intencionales
#                                 para validar que el código NO es vulnerable.
#   - scripts/hooks/git-gate.py  → gate Python pre-push, no shell con sqlite3.
#   - scripts/test-teamdb-safe.sh,
#     scripts/test-teamdb-git-sync.sh → fixtures de test bajo scripts/ (no
#                                 tests/ por legacy de nombres); slugs/valores
#                                 hardcodeados en asserts, mismo caso que
#                                 tests/**.
#   - scripts/migrate-legacy-md-to-db.sh → `SELECT COUNT(*) FROM $t` interpola
#                                 un nombre de TABLA, no un valor; $t itera un
#                                 enum fijo definido en la misma línea de arriba
#                                 (concepts/decisions/work_in_progress/
#                                 preferences/known_problems), nunca input
#                                 externo. Los `?` de sqlite3 no bindean
#                                 identificadores de tabla/columna, así que esto
#                                 no es parametrizable — es el patrón correcto.
# La lista se materializa en el flag --exclude de .github/workflows/lint-sqli.yml.
# Si agregás una excepción nueva, actualizá AMBOS: este comentario y el workflow.
#
# ─── Excepción de línea puntual: `# lens:ok <motivo>` ──────────────────────────
# Para un caso aislado dentro de un archivo que por lo demás sí queremos
# revisado (no amerita excluir el archivo entero), se puede marcar la línea
# exacta con un comentario al final: `algo-riesgoso  # lens:ok: por qué es
# seguro`. El motivo queda al lado del código, visible en cualquier diff o
# blame — no en un YAML aparte que nadie relee. Usar con criterio: es una
# excepción por línea, no una forma de silenciar el lens en general.
#
# Uso: bash skalling-review.sh [--lens risk|resilience|readability|reliability|all]
#                              [--cwd <dir>] [--diff <range>]
#                              [--deep] [--collect <bundle-dir>]
#                              [--scope <glob>] [--exclude <csv>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Kill switch (se evalúa antes que nada: ni siquiera parsea args)
if [ "${SKALLING_REVIEW_MODE:-on}" = "off" ]; then
  echo "skalling-review: desactivado (SKALLING_REVIEW_MODE=off)"
  exit 0
fi

LENS="all"
CWD="$(pwd)"
DIFF_RANGE=""
DEEP=0
COLLECT_DIR=""
SCOPE=""
EXCLUDE=""

usage() {
  echo "Uso: bash skalling-review.sh [--lens risk|resilience|readability|reliability|all] [--cwd <dir>] [--diff <range>] [--deep] [--collect <bundle-dir>] [--scope <glob>] [--exclude <csv>]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lens)
      LENS="${2:-all}"
      shift 2
      ;;
    --cwd)
      CWD="$2"
      shift 2
      ;;
    --diff)
      DIFF_RANGE="$2"
      shift 2
      ;;
    --deep)
      DEEP=1
      shift
      ;;
    --collect)
      COLLECT_DIR="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --exclude)
      EXCLUDE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Arg desconocido: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

RUN_RISK=0 RUN_RESILIENCE=0 RUN_READABILITY=0 RUN_RELIABILITY=0
case "$LENS" in
  all)       RUN_RISK=1 RUN_RESILIENCE=1 RUN_READABILITY=1 RUN_RELIABILITY=1 ;;
  risk)      RUN_RISK=1 ;;
  resilience) RUN_RESILIENCE=1 ;;
  readability) RUN_READABILITY=1 ;;
  reliability) RUN_RELIABILITY=1 ;;
  *)
    echo "Lens inválido: $LENS" >&2
    usage >&2
    exit 2
    ;;
esac

PROJECT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$PROJECT" ]; then
  echo "ERROR: $CWD no es un repositorio git" >&2
  exit 2
fi

# ── Helpers para modo --scope (CI gate lint-sqli.yml) ──
# Definidos aquí (antes de su uso en línea ~269) porque bash registra funciones
# en runtime, no eagerly: si se llaman antes de llegar a su `function_name() {`,
# fallan con "command not found".

# build_scope_filelist: emite paths tracked que matchean <glob>, uno por línea,
# saltando los listados en <csv>. Pensado para diff_files en modo --scope.
# NOTA: el pattern va SIN comillas en el `case` para que bash expanda `*` y
# `**` como glob (pathname expansion). Si se pone `"$scope_glob"`, bash trata
# el `*` como literal y NUNCA matchea. Soporta `**` traduciéndolo a `*` porque
# bash 3.2 (macOS) no tiene globstar; el case-pattern de bash expande `*` a
# "cualquier secuencia incluso con /", así que `scripts/*` matchea todo lo
# debajo de scripts/ incluyendo subdirectorios.
build_scope_filelist() {
  local scope_glob="$1"
  local excludes_csv="$2"
  local file
  # `**` → `*` (bash 3.2 case-pattern ya trata `*` como "cualquier cosa")
  local scope_pat="${scope_glob//\*\*/*}"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    # sin comillas alrededor de $scope_pat para permitir expansión de glob
    case "$file" in
      $scope_pat) ;;
      *) continue ;;
    esac
    if [ -n "$excludes_csv" ]; then
      case ",${excludes_csv}," in
        *,"$file,"*) continue ;;
      esac
    fi
    printf '%s\n' "$file"
  done < <(git -C "$PROJECT" ls-files 2>/dev/null || true)
}

# build_scope_diff: arma un diff sintético donde cada archivo en scope aparece
# con todas sus líneas marcadas como added. Esto permite que `added_lines` y los
# lenses corran el mismo flujo que con un diff real, sin staged changes.
build_scope_diff() {
  local scope_glob="$1"
  local excludes_csv="$2"
  local file line_count line
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    local full_path="$PROJECT/$file"
    [ -f "$full_path" ] || continue
    line_count=$(wc -l < "$full_path" | tr -d ' ')
    if [ "$line_count" = "0" ]; then
      # wc -l devuelve 0 para archivos sin trailing newline; también si el archivo está vacío.
      printf '%s\n' "--- a/$file"
      printf '%s\n' "+++ b/$file"
      printf '%s\n' "@@ -0,0 +1,1 @@"
      printf '%s\n' "+"
      continue
    fi
    printf '%s\n' "--- a/$file"
    printf '%s\n' "+++ b/$file"
    printf '%s\n' "@@ -0,0 +1,$line_count @@"
    # Marcar cada línea como added; preservar contenido literal (los `+` que
    # pudiera haber en el código fuente se interpretan como prefijo de diff, no
    # como contenido — el parser de added_lines los maneja tal cual).
    while IFS= read -r line; do
      printf '%s\n' "+$line"
    done < "$full_path"
  done < <(build_scope_filelist "$scope_glob" "$excludes_csv")
}

# ── Modo --collect: incorpora findings de agentes (resultado de --deep) ──
# Lee findings-<lens>.json del bundle congelado; cualquier BLOCKER falla el
# review (exit 1, mismo contrato de severidad que los lenses heurísticos).
# Contrato del JSON (escrito por agentes en --deep):
#   [ {"file": "ruta", "line": 12, "severity": "BLOCKER|WARNING|SUGGESTION", "message": "..."} ]
# CONTRATO DE AUSENCIA (fail-closed, v0.8.3): un lens SELECCIONADO sin
# findings-<lens>.json = el agente no reportó = 1 BLOCKER → el review FALLA,
# NUNCA es PASS. Un bundle sin NINGÚN findings-*.json (recién creado/vacío)
# también FAIL con mensaje claro: sellar un PASS sin evidencia de revisión
# sería un falso green. Antes el archivo ausente era WARN + continue → 0
# blockers → PASS sin revisión (contrato inconsistente: el JSON ilegible ya era
# BLOCKER; el archivo ausente no podía ser PASS silencioso).
if [ -n "$COLLECT_DIR" ]; then
  if [ ! -d "$COLLECT_DIR" ]; then
    echo "ERROR: bundle no encontrado: $COLLECT_DIR" >&2
    exit 2
  fi
  TREE_HASH="$(basename "$COLLECT_DIR")"
  # Bundle sin ningún findings-*.json → no hay resultados que incorporar.
  N_FINDINGS="$(find "$COLLECT_DIR" -maxdepth 1 -name 'findings-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$N_FINDINGS" = "0" ]; then
    echo "ERROR: bundle sin resultados de agentes — no hay findings-*.json en $COLLECT_DIR" >&2
    echo "       Corré --deep y esperá a que los agentes escriban findings antes de --collect." >&2
    exit 1
  fi
  BLOCKERS=0
  WARNINGS=0
  SUGGESTS=0

  for lens in risk resilience readability reliability; do
    # Solo lenses seleccionados (--lens all = los 4)
    case "$LENS" in
      all) ;;
      "$lens") ;;
      *) continue ;;
    esac
    JSON="$COLLECT_DIR/findings-$lens.json"
    if [ ! -f "$JSON" ]; then
      # Fail-closed (bug B): lens seleccionado sin findings = el agente no
      # revisó → 1 BLOCKER. Un lens que no reportó NUNCA puede pasar el review.
      echo "✗ [BLOCKER][$lens] findings-$lens.json no existe — el agente del lens $lens no reportó findings" >&2
      BLOCKERS=$((BLOCKERS + 1))
      continue
    fi
    OUT="$(python3 - "$JSON" "$lens" <<'PYEOF'
import json, sys
path, lens = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("se esperaba una lista de findings")
except Exception as e:
    # Fail-closed: findings ilegible = 1 BLOCKER, nunca PASS silencioso.
    print("\u2717 [BLOCKER][%s] findings-%s.json \u2014 resultado ilegible: %s" % (lens, lens, e))
    print("COUNTS|1|0|0")
    sys.exit(0)
blocker = warning = suggest = 0
for item in data:
    if not isinstance(item, dict):
        continue
    sev = str(item.get("severity", "SUGGESTION")).upper()
    if sev not in ("BLOCKER", "WARNING", "SUGGESTION"):
        sev = "SUGGESTION"
    if sev == "BLOCKER":
        blocker += 1
    elif sev == "WARNING":
        warning += 1
    else:
        suggest += 1
    loc = str(item.get("file", "?"))
    line = item.get("line")
    if line not in (None, ""):
        loc = "%s:%s" % (loc, line)
    msg = str(item.get("message", "")).replace("\n", " ").strip()
    icon = "\u2717" if sev == "BLOCKER" else ("\u26a0" if sev == "WARNING" else "\u2713")
    print("%s [%s][%s] %s \u2014 %s" % (icon, sev, lens, loc, msg))
print("COUNTS|%s|%s|%s" % (blocker, warning, suggest))
PYEOF
    )" || true
    # Mostrar findings (todo menos la línea COUNTS)
    printf '%s\n' "$OUT" | grep -vF 'COUNTS|'
    COUNTS_LINE="$(printf '%s\n' "$OUT" | grep -F 'COUNTS|' | tail -1 || true)"
    IFS='|' read -r _ B W S <<< "$COUNTS_LINE"
    BLOCKERS=$((BLOCKERS + ${B:-0}))
    WARNINGS=$((WARNINGS + ${W:-0}))
    SUGGESTS=$((SUGGESTS + ${S:-0}))
  done

  TOTAL=$((BLOCKERS + WARNINGS + SUGGESTS))
  if [ "$BLOCKERS" -eq 0 ]; then
    RESULT="PASS"
    RC=0
  else
    RESULT="FAIL"
    RC=1
  fi
  SUMMARY="{\"collect\":true,\"blocker\":$BLOCKERS,\"warning\":$WARNINGS,\"total\":$TOTAL,\"tree_hash\":\"$TREE_HASH\"}"

  # Sellar el receipt con el tree_hash del bundle (misma senda best-effort).
  DB="$(teamdb_project_path "$PROJECT")"
  if [ -f "$DB" ]; then
    TASK_ID="${SKALLING_TASK_ID:-review}"
    AGENT="${SKALLING_REVIEW_AGENT:-luz}"
    SEAL_CMD="review --collect $(basename "$COLLECT_DIR") --lens $LENS"
    if ! TEAMDB_CLAIM_COMMAND="$SEAL_CMD" \
          TEAMDB_CLAIM_EXIT_CODE="$RC" \
          TEAMDB_CLAIM_TREE_HASH="$TREE_HASH" \
          TEAMDB_CLAIM_OUTPUT_SUMMARY="$SUMMARY" \
          bash "$SCRIPT_DIR/teamdb-seal-receipt.sh" "$TASK_ID" "$AGENT" "$PROJECT" >/dev/null 2>&1; then
      echo "WARN: no se pudo sellar receipt de review" >&2
    fi
  else
    echo "WARN: no hay team.db ($DB); receipt de review NO sellado" >&2
  fi

  echo "REVIEW: $RESULT ($TOTAL findings, $BLOCKERS blockers, vía --collect)"
  exit "$RC"
fi

# Candidato a revisar: diff y hash congelado (mismo criterio que el seal).
# Siempre excluye db/teamdb/team.dump.sql (artefacto derivado).
DUMP_EXCLUDE='-- . :(exclude)db/teamdb/team.dump.sql'
if [ -n "$DIFF_RANGE" ]; then
  DIFF_TEXT="$(git -C "$PROJECT" diff "$DIFF_RANGE" $DUMP_EXCLUDE 2>/dev/null || true)"
  TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
elif [ -n "$SCOPE" ]; then
  # ── Modo --scope: CI gate (lint-sqli.yml). Construye un diff sintético donde
  # todas las líneas de los archivos en scope aparecen como added, para que
  # `added_lines` las procese con el mismo código del lens_risk sin tener que
  # preparar un diff staged. Pensado para escaneo completo, no incremental.
  DIFF_TEXT="$(build_scope_diff "$SCOPE" "$EXCLUDE")"
  TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
else
  DIFF_TEXT="$(git -C "$PROJECT" diff --cached $DUMP_EXCLUDE 2>/dev/null || true)"
  if [ -n "$DIFF_TEXT" ]; then
    TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
  else
    echo "ERROR: nada preparado para revisar. Preparar únicamente los archivos autorizados." >&2
    exit 1
  fi
fi

# ── Modo --deep: congela el diff y genera material para delegar a subagentes ──
# El script NO lanza subagentes: produce el bundle y los prompts; luego
# --collect incorpora los findings-<lens>.json que los agentes escriban.
lens_agent() {
  case "$1" in
    risk) echo "agents-base/Luz.md" ;;
    resilience) echo "agents-base/Jhon.md" ;;
    readability) echo "agents-base/Pau.md" ;;
    reliability) echo "agents-base/Jhon.md" ;;
    *) echo "" ;;
  esac
}

lens_guide() {
  case "$1" in
    risk)
      cat <<'EOF'
- `eval` sin comillas o con variable interpolada
- `rm -rf` sin guarda de ruta (sin verificación previa de la variable objetivo)
- `curl`/`wget` con `-k`/`--insecure`
- URLs `http://` en vez de `https://`
- `chmod 777`
- Secretos hardcodeados (api_key, secret, password, token, ...)
- SQL injection: variables interpoladas en queries de `sqlite3`
EOF
      ;;
    resilience)
      cat <<'EOF'
- Scripts sin `set -euo pipefail`
- `mktemp -d` sin trap de cleanup (EXIT)
- Locks (`teamdb_lock`) sin timeout
- Loops `while read` sin contador ni timeout
EOF
      ;;
    readability)
      cat <<'EOF'
- Comentarios TODO/FIXME/HACK
- Líneas > 120 chars
- Nombres de variable genéricos (tmp, x, foo, bar)
- Funciones > 50 líneas y archivos > 400 líneas
- Estructura y nombres que no revelan intención
EOF
      ;;
    reliability)
      cat <<'EOF'
- Scripts/modulos nuevos sin test que los cubra
- Tests sin asserts ni PASS counter
- Chequeos que dependen del entorno (paths frágiles, binaries no verificados)
EOF
      ;;
  esac
}

deep_generate() {
  local lens agent guide
  local review_dir="$PROJECT/.opencode/context/review/$TREE_HASH"
  if [ -d "$review_dir" ]; then
    echo "WARN: bundle ya existe para $TREE_HASH (idempotente, no se sobreescribe): $review_dir" >&2
  else
    mkdir -p "$review_dir"
    printf '%s' "$DIFF_TEXT" > "$review_dir/candidate.diff"
    if [ -n "$DIFF_RANGE" ]; then
      # shellcheck disable=SC2086
      git -C "$PROJECT" diff $DIFF_RANGE --name-status > "$review_dir/files.txt" 2>/dev/null || true
    else
      git -C "$PROJECT" diff --cached --name-status > "$review_dir/files.txt" 2>/dev/null || true
    fi

    for lens in risk resilience readability reliability; do
      # Solo lenses seleccionados (--lens all = los 4)
      case "$LENS" in
        all) ;;
        "$lens") ;;
        *) continue ;;
      esac
      agent="$(lens_agent "$lens")"
      guide="$(lens_guide "$lens")"
      {
        echo "# Revisión delegada — lens $lens"
        echo ""
        echo "Rol del agente: \`$agent\` (cargá ese archivo de rol para alinearte con su responsabilidad)."
        echo ""
        echo "## Regla de oro"
        echo "REVISÁ SOLO EL DIFF CONGELADO (candidate.diff de este bundle). NO leas el working tree:"
        echo "los archivos pueden haber cambiado desde que se congeló el candidato."
        echo ""
        echo "## Qué buscar ($lens)"
        printf '%s\n' "$guide"
        echo ""
        echo "## Archivos del candidato (name-status)"
        echo '```'
        cat "$review_dir/files.txt" 2>/dev/null || true
        echo '```'
        echo ""
        echo "## Diff congelado"
        echo '```diff'
        cat "$review_dir/candidate.diff"
        echo '```'
        echo ""
        echo "## Formato de salida"
        echo "Escribí tus findings en $review_dir/findings-$lens.json con este formato exacto:"
        echo '[{"file": "ruta/al/archivo", "line": 12, "severity": "BLOCKER|WARNING|SUGGESTION", "message": "descripción corta"}]'
        echo ""
        echo "Severidad: BLOCKER (bloquea el merge), WARNING (a corregir idealmente), SUGGESTION (mejora opcional)."
      } > "$review_dir/prompt-$lens.md"
    done
  fi
  echo "Bundle congelado: $review_dir"
  echo ""
  echo "Delegación sugerida (un subagente por lens; el orchestrator la ejecuta):"
  for lens in risk resilience readability reliability; do
    case "$LENS" in
      all) ;;
      "$lens") ;;
      *) continue ;;
    esac
    agent="$(basename "$(lens_agent "$lens")" .md)"
    echo "  lens $lens → agente $agent: prompt en $review_dir/prompt-$lens.md"
    echo "             findings → $review_dir/findings-$lens.json"
  done
  echo ""
  echo "Cuando los agentes terminen, incorporá resultados:"
  echo "  bash $0 --collect $review_dir --lens $LENS"
}

if [ "$DEEP" = "1" ]; then
  deep_generate
  exit 0
fi

# ── Estructura de findings ──
FINDINGS=()
BLOCKERS=0
WARNINGS=0
INFO_COUNT=0

add_finding() {
  local sev="$1"
  local lens="$2"
  local loc="$3"
  local msg="$4"
  FINDINGS+=("$sev|$lens|$loc|$msg")
  case "$sev" in
    BLOCKER) BLOCKERS=$((BLOCKERS + 1)) ;;
    WARNING) WARNINGS=$((WARNINGS + 1)) ;;
    *) INFO_COUNT=$((INFO_COUNT + 1)) ;;
  esac
}

# added_lines: imprime "file<TAB>newline<TAB>content" para las líneas AÑADIDAS
# del diff (con número de línea real en el archivo nuevo).
added_lines() {
  local diff_text="$1"
  local file="" newline=0 line new_sec content
  while IFS= read -r line; do
    case "$line" in
      '+++ '*)
        file="${line#+++ }"
        file="${file#b/}"
        ;;
      '@@'*)
        new_sec="$(printf '%s' "$line" | sed -n 's/^@@[^+]*+\([0-9]*\)[^@]*@@.*/\1/p')"
        if [ -n "$new_sec" ]; then
          newline=$((new_sec - 1))
        fi
        ;;
      '+'*)
        newline=$((newline + 1))
        if [ -n "$file" ]; then
          content="${line#+}"
          printf '%s\t%s\t%s\n' "$file" "$newline" "$content"
        fi
        ;;
    esac
  done <<< "$diff_text"
}

# diff_files: nombres de archivos del candidato (mismo rango que el diff).
diff_files() {
  if [ -n "$DIFF_RANGE" ]; then
    # shellcheck disable=SC2086
    git -C "$PROJECT" diff $DIFF_RANGE --name-only 2>/dev/null || true
  elif [ -n "$SCOPE" ]; then
    # Modo --scope: lista archivos tracked que matchean el glob (excluyendo los de --exclude).
    build_scope_filelist "$SCOPE" "$EXCLUDE"
  else
    git -C "$PROJECT" diff --cached --name-only 2>/dev/null || true
  fi
}

# rm_targets_are_mktemp <file> <content>
# true si TODAS las variables ($VAR o ${VAR}) referenciadas en <content> (la
# línea del rm) fueron asignadas vía `mktemp` en algún lugar de <file>. Exige
# que TODAS lo sean (no alguna) para no aflojar de más una línea que mezcla
# una var segura con una que no lo es (ej: `rm -rf "$TMP_DIR" "$USER_INPUT"`).
rm_targets_are_mktemp() {
  local file="$1" content="$2" var found_any=0
  [ -f "$file" ] || return 1
  for var in $(printf '%s' "$content" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | tr -d '${}' | sort -u); do
    found_any=1
    grep -qE "^[[:space:]]*(local[[:space:]]+)?${var}=.*mktemp" "$file" || return 1
  done
  [ "$found_any" = "1" ]
}

# ── Lens risk ──
lens_risk() {
  local diff_text="$1"
  local file ln content lines content_trim
  local pat_eval='eval[[:space:]]+'
  local pat_eval_var="eval[[:space:]]+[\"']?\\\$"
  local pat_eval_quoted="eval[[:space:]]*['\"]"
  local pat_rm='rm[[:space:]]+-[rf]+'
  # Guardas que NO protegen las rutas BARE del sistema: al negar con substring,
  # incluir /var/tmp/ en el guard "protegería" también a `rm -rf /var/tmp/*`
  # (las rutas absolutas del sistema van en pat_rm_sys, chequeo positivo aparte).
  # $TMP/$TMPDIR/$HOME y ~/ sí son variables controladas (dependen de la sesión,
  # no son destructivas por sí solas); `[ -n/-z/-f/-d ]` en la MISMA línea es la
  # verificación previa que exige el repo antes de rm sobre una variable.
  # NOTA (revisado): $TMP_DIR/$TARGET_DIR YA NO son BLOCKER automático si la
  # MISMA variable objetivo del rm fue asignada vía `mktemp` en el archivo —
  # ver rm_targets_are_mktemp() más abajo. mktemp garantiza una ruta única y
  # no vacía por construcción (y bajo `set -e` el script aborta antes de llegar
  # al rm si mktemp falla); exigir además un `[ -n ]` en la misma línea es
  # verificación redundante, no protección real. Cualquier otra variable propia
  # (no-mktemp) sigue exigiendo guarda explícita en la misma línea.
  local pat_rm_guard='\$TMPDIR|\$TMP\b|\$HOME|~/|\[[[:space:]]+-[nzfd]'
  local pat_rm_sys='rm[[:space:]]+-[rf]+[[:space:]]+/(tmp|var/tmp|var/folders)/'
  local pat_curl='(curl|wget)[^|;]*( -k|--insecure)'
  local pat_http='http://'
  local pat_chmod='chmod[[:space:]]+777'
  # Requiere valor entre comillas SIN '$' adentro (6+ chars): descarta
  # placeholders de bind (`token=?`) y valores generados en runtime
  # (`token="atmp_$(...)"`) sin dejar de detectar un literal hardcodeado real
  # (`password="hunter2ABCDEF"`). "token" se sacó de la lista de keywords: es
  # genérico (locks, request tokens) y produce ruido; los tokens reales con
  # forma de credencial (ghp_/sk-/AIza/AKIA/Bearer) ya los cubre git-gate.py
  # con prefijos específicos, más preciso que este heurístico por palabra.
  local pat_secret="(api[_-]?key|secret|password|passwd)[[:space:]]*=[[:space:]]*[\"'][^\"'\$]{6,}[\"']"  # lens:ok: definición del propio patrón, no un secreto real (mismo caso que pat_sqli/pat_sqli_dq)
  # SQL injection (pat_sqli + pat_sqli_dq). Coincide con código del estilo
  # `sqlite3 "$DB" "...'$VAR..."` o `sqlite3 "$DB" "...\"$VAR...\""`. Riesgo:
  # si $VAR contiene `';DROP TABLE ...;--` u otros payloads, el SQL se ejecuta.
  # EXCEPCIONES (ver cabecera): estos archivos matchean por diseño, no por bug:
  #   - scripts/lib/lib-teamdb.sh       (provee _sql_quote + teamdb_exec_value)
  #   - scripts/skalling-review.sh      (define estos patrones como regex)
  #   - scripts/teamdb_exec.py          (wrapper Python con real bind params)
  #   - tests/**                        (fixtures con payloads SQLi)
  #   - scripts/hooks/git-gate.py       (gate Python, no shell con sqlite3)
  # Las exclusiones se materializan en .github/workflows/lint-sqli.yml via
  # `--exclude` (no en este script — operate on diff, no on file path).
  local pat_sqli="sqlite3[^;]*'\\\$[A-Za-z_]"
  # Interpolación de variables dentro de la QUERY (comillas dobles). Pide keyword
  # SQL (SELECT/INSERT/UPDATE/DELETE) en la MISMA línea para no apuntar al path
  # `"$DB"` suelto; `$(` (command substitution) no matchea por [A-Za-z_], así
  # `$(_sql_quote "$x")` — el escape seguro que ya usa el repo — NO da falso
  # positivo (antes el falso negativo: `id = $ID` dentro de comillas se escapaba).
  local pat_sqli_dq='sqlite3[^;]*"[^"]*(SELECT|INSERT|UPDATE|DELETE)[^"]*\$[A-Za-z_][A-Za-z0-9_]*'

  while IFS=$'\t' read -r file ln content; do
    # Saltar líneas comentadas: el lens mira código ejecutable, no ejemplos
    # (un `# eval "$x"` documentando un anti-patrón no es un riesgo real).
    content_trim="$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//')"
    case "$content_trim" in
      \#*) continue ;;
    esac
    # Marcador de excepción auditable: un humano revisó ESTA línea puntual y
    # dejó por qué es segura, en vez de ensanchar una regex genérica para un
    # caso puntual (ej: ruta fija construida una vez, loop ya validado por un
    # `case` previo). Vive en el diff, no en un YAML aparte — se ve al lado
    # del código que justifica. Formato: `# lens:ok <motivo>` al final de línea.
    case "$content" in
      *'# lens:ok'*) continue ;;
    esac
    if printf '%s' "$content" | grep -qE "$pat_eval" \
       && ! printf '%s' "$content" | grep -qE "$pat_eval_quoted"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "eval sin comillas"
    elif printf '%s' "$content" | grep -qE "$pat_eval_var"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "eval con variable"
    fi
    if printf '%s' "$content" | grep -qE "$pat_rm"; then
      if printf '%s' "$content" | grep -qE "$pat_rm_sys"; then
        add_finding "BLOCKER" "risk" "$file:$ln" "rm -rf sobre ruta temp del sistema (/tmp,/var/tmp,/var/folders)"
      elif ! printf '%s' "$content" | grep -qE "$pat_rm_guard" \
           && ! rm_targets_are_mktemp "$file" "$content"; then
        add_finding "BLOCKER" "risk" "$file:$ln" "rm -rf sin guarda de ruta"
      fi
    fi
    if printf '%s' "$content" | grep -qE "$pat_curl"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "curl/wget con -k/--insecure"
    fi
    if printf '%s' "$content" | grep -qE "$pat_http"; then
      add_finding "WARNING" "risk" "$file:$ln" "URL http:// (usá https)"
    fi
    if printf '%s' "$content" | grep -qE "$pat_chmod"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "chmod 777"
    fi
    if printf '%s' "$content" | grep -qiE "$pat_secret"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "secreto hardcodeado"
    fi
    if printf '%s' "$content" | grep -qE "$pat_sqli"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "posible SQL injection: variable interpolada en query sqlite3"
    elif printf '%s' "$content" | grep -qE "$pat_sqli_dq"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "posible SQL injection: variable interpolada en query sqlite3 (comillas dobles)"
    fi
  done <<< "$(added_lines "$diff_text")"
}

# ── Lens resilience ──
lens_resilience() {
  local file
  local pat_lock_timeout='teamdb_lock[[:space:]]+[^)]*[0-9]'
  local pat_loop_guard='\$\{?[A-Za-z_]+[^}]*\}|for[[:space:]]+[A-Za-z_]+[[:space:]]+in[[:space:]]+\(|seq[[:space:]]|count[=+]|max_[0-9]|\$\(\(|/dev/urandom'
  local sh_file
  for file in $(diff_files); do
    case "$file" in
      *.sh)
        sh_file="$PROJECT/$file"
        if [ -f "$sh_file" ]; then
          if ! grep -q 'set -euo pipefail' "$sh_file"; then
            add_finding "WARNING" "resilience" "$file" "script sin set -euo pipefail"
          fi
          if grep -q 'mktemp -d' "$sh_file" \
             && ! grep -qE "trap[[:space:]].*EXIT|trap[[:space:]].*cleanup|rm -rf \"\$TMP" "$sh_file"; then
            add_finding "WARNING" "resilience" "$file" "mktemp -d sin trap de cleanup"
          fi
          if grep -q 'teamdb_lock' "$sh_file" \
             && ! grep -qE "$pat_lock_timeout" "$sh_file"; then
            add_finding "WARNING" "resilience" "$file" "teamdb_lock sin timeout"
          fi
          if grep -qE 'while[[:space:]]+.*read[[:space:]]' "$sh_file" \
             && ! grep -qE "$pat_loop_guard" "$sh_file"; then
            add_finding "INFO" "resilience" "$file" "loops while read sin contador ni timeout"
          fi
        fi
        ;;
    esac
  done
}

# ── Lens readability ──
lens_readability() {
  local diff_text="$1"
  local file ln content
  local pat_generic='\b(tmp|x|foo|bar|a|b)\b[[:space:]]*='

  while IFS=$'\t' read -r file ln content; do
    if printf '%s' "$content" | grep -qE 'TODO|FIXME|HACK'; then
      add_finding "WARNING" "readability" "$file:$ln" "comentario TODO/FIXME/HACK"
    fi
    if [ "${#content}" -gt 120 ]; then
      add_finding "WARNING" "readability" "$file:$ln" "línea de ${#content} chars (>120)"
    fi
    if printf '%s' "$content" | grep -qE "$pat_generic"; then
      add_finding "WARNING" "readability" "$file:$ln" "nombre de variable genérico"
    fi
  done <<< "$(added_lines "$diff_text")"

  # Chequeos por archivo completo
  local sh_file lines
  for file in $(diff_files); do
    case "$file" in
      *.sh)
        sh_file="$PROJECT/$file"
        if [ -f "$sh_file" ]; then
          lines=$(wc -l < "$sh_file" | tr -d ' ')
          if [ "$lines" -gt 400 ]; then
            add_finding "WARNING" "readability" "$file" "archivo de $lines líneas (>400)"
          fi
          # Funciones largas (>50 líneas): aproximación por span entre definiciones
          if awk '/^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ { if (s>0 && NR-s>50) print s":"NR; s=NR }
                  END { if (s>0 && NR-s>50) print s":"NR }' "$sh_file" | grep -q .; then
            add_finding "WARNING" "readability" "$file" "función >50 líneas"
          fi
        fi
        ;;
    esac
  done
}

# ── Lens reliability ──
lens_reliability() {
  local file base
  local tests_dir="$PROJECT/tests"
  for file in $(diff_files); do
    case "$file" in
      tests/*)
        # Cambios en tests/ que no tienen asserts ni PASS counter
        if [ -f "$PROJECT/$file" ]; then
          if ! grep -qE 'assert_|PASS=' "$PROJECT/$file"; then
            add_finding "WARNING" "reliability" "$file" "test sin assert_ ni PASS counter"
          fi
        fi
        ;;
      scripts/*|*.sh)
        if [ "$file" = "*.sh" ]; then
          continue
        fi
        base="$(basename "$file")"
        if [ -d "$tests_dir" ]; then
          if ! grep -l "$base" "$tests_dir"/*.sh >/dev/null 2>&1; then
            add_finding "WARNING" "reliability" "$file" "script sin test que lo cubra"
          fi
        else
          add_finding "WARNING" "reliability" "$file" "no hay tests/ en el repo"
        fi
        ;;
    esac
  done
}

# ── Ejecutar lenses seleccionados ──
[ "$RUN_RISK" = "1" ] && lens_risk "$DIFF_TEXT"
[ "$RUN_RESILIENCE" = "1" ] && lens_resilience
[ "$RUN_READABILITY" = "1" ] && lens_readability "$DIFF_TEXT"
[ "$RUN_RELIABILITY" = "1" ] && lens_reliability

# ── Salida legible ──
count_for() {
  local sev="$1" lens="$2" n=0 f
  if [ "${FINDINGS+x}" = "x" ]; then
    for f in "${FINDINGS[@]}"; do
      case "$f" in
        "$sev|$lens"*) n=$((n + 1)) ;;
      esac
    done
  fi
  echo "$n"
}

if [ "${FINDINGS+x}" = "x" ]; then
  for finding in "${FINDINGS[@]}"; do
    sev="${finding%%|*}"
    rest="${finding#*|}"
    lens="${rest%%|*}"
    rest="${rest#*|}"
    loc="${rest%%|*}"
    msg="${rest#*|}"
    case "$sev" in
      BLOCKER) echo "✗ [BLOCKER][$lens] $loc — $msg" ;;
      WARNING) echo "⚠ [WARNING][$lens] $loc — $msg" ;;
      *) echo "✓ [INFO][$lens] $loc — $msg" ;;
    esac
  done
fi

TOTAL=$((BLOCKERS + WARNINGS + INFO_COUNT))
if [ "$BLOCKERS" -eq 0 ]; then
  RESULT="PASS"
  RC=0
else
  RESULT="FAIL"
  RC=1
fi

SUMMARY="{\"risk\":{\"blocker\":$(count_for BLOCKER risk),\"warning\":$(count_for WARNING risk)},\
\"resilience\":{\"blocker\":$(count_for BLOCKER resilience),\"warning\":$(count_for WARNING resilience)},\
\"readability\":{\"blocker\":$(count_for BLOCKER readability),\"warning\":$(count_for WARNING readability)},\
\"reliability\":{\"blocker\":$(count_for BLOCKER reliability),\"warning\":$(count_for WARNING reliability)},\
\"total\":$TOTAL,\"tree_hash\":\"$TREE_HASH\"}"

# Receipt sellado (best-effort; el exit code final lo definen los blockers)
DB="$(teamdb_project_path "$PROJECT")"
if [ -f "$DB" ]; then
  TASK_ID="${SKALLING_TASK_ID:-review}"
  AGENT="${SKALLING_REVIEW_AGENT:-luz}"
  SEAL_CMD="review --lens $LENS${DIFF_RANGE:+ --diff $DIFF_RANGE}"
  if ! TEAMDB_CLAIM_COMMAND="$SEAL_CMD" \
        TEAMDB_CLAIM_EXIT_CODE="$RC" \
        TEAMDB_CLAIM_TREE_HASH="$TREE_HASH" \
        TEAMDB_CLAIM_OUTPUT_SUMMARY="$SUMMARY" \
        bash "$SCRIPT_DIR/teamdb-seal-receipt.sh" "$TASK_ID" "$AGENT" "$PROJECT" >/dev/null 2>&1; then
    echo "WARN: no se pudo sellar receipt de review" >&2
  fi
else
  echo "WARN: no hay team.db ($DB); receipt de review NO sellado" >&2
fi

echo "REVIEW: $RESULT ($TOTAL findings, $BLOCKERS blockers)"
exit "$RC"
