#!/usr/bin/env bash
# skalling-review.sh — Revisión estructurada con 4 lenses (bash/sqlite)
# v0.8.3: reemplaza la revisión visual por un análisis de patrones sobre el diff.
#   risk         → eval/rm -rf/curl -k/http:///secretos/chmod 777/SQL injection
#   resilience   → set -euo pipefail, mktemp sin trap, locks sin timeout
#   readability  → funciones largas, vars genéricas, TODO/FIXME/HACK, líneas largas
#   reliability  → scripts sin test que los cubra, tests sin asserts
# Kill switch: SKALLING_REVIEW_MODE=off desactiva (default: on).
# Uso: bash skalling-review.sh [--lens risk|resilience|readability|reliability|all]
#                              [--cwd <dir>] [--diff <range>]
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

usage() {
  echo "Uso: bash skalling-review.sh [--lens risk|resilience|readability|reliability|all] [--cwd <dir>] [--diff <range>]"
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

# Candidato a revisar: diff y hash congelado (mismo criterio que el seal).
if [ -n "$DIFF_RANGE" ]; then
  DIFF_TEXT="$(git -C "$PROJECT" diff "$DIFF_RANGE" 2>/dev/null || true)"
  TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
else
  DIFF_TEXT="$(git -C "$PROJECT" diff HEAD 2>/dev/null || true)"
  if [ -n "$DIFF_TEXT" ]; then
    TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
  else
    TREE_HASH="$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null | cut -c1-16)"
  fi
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
  else
    git -C "$PROJECT" diff HEAD --name-only 2>/dev/null || true
  fi
}

# ── Lens risk ──
lens_risk() {
  local diff_text="$1"
  local file ln content lines
  local pat_eval='eval[[:space:]]+'
  local pat_eval_var="eval[[:space:]]+[\"']?\\\$"
  local pat_eval_quoted="eval[[:space:]]*['\"]"
  local pat_rm='rm[[:space:]]+-[rf]+'
  local pat_rm_guard='\$TMP|/tmp/|/var/folders|\[[[:space:]]+-[nzfd]'
  local pat_curl='(curl|wget)[^|;]*( -k|--insecure)'
  local pat_http='http://'
  local pat_chmod='chmod[[:space:]]+777'
  local pat_secret="(api[_-]?key|secret|password|passwd|token)[[:space:]]*=[[:space:]]*[\"']?[^\"'[:space:]$]"
  local pat_sqli="sqlite3[^;]*'\\\$[A-Za-z_]"

  while IFS=$'\t' read -r file ln content; do
    if printf '%s' "$content" | grep -qE "$pat_eval" \
       && ! printf '%s' "$content" | grep -qE "$pat_eval_quoted"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "eval sin comillas"
    elif printf '%s' "$content" | grep -qE "$pat_eval_var"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "eval con variable"
    fi
    if printf '%s' "$content" | grep -qE "$pat_rm" \
       && ! printf '%s' "$content" | grep -qE "$pat_rm_guard"; then
      add_finding "BLOCKER" "risk" "$file:$ln" "rm -rf sin guarda de ruta"
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
