#!/usr/bin/env bash
# tests/scripts-parity.test.sh — Validación del bundle local .opencode/scripts/
# Fase 2 (scripts-parity-phase2). Patrón similar a tests/teamdb-claim-lease.test.sh.
#
# Casos:
#   1. --check retorna 0 cuando el bundle está sincronizado.
#   2. .opencode/scripts/ no contiene huérfanos (whitelist = manifest).
#   3. Simulación de drift en directorio aislado: --check retorna ≠0.
#   4. Idempotencia: --apply en directorio aislado sin cambios mantiene sha256.
#   5. --dry-run no escribe ni toca el árbol real.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
SNAPSHOT="$ROOT/scripts/build-local-snapshot.sh"
MANIFEST="$ROOT/scripts/.bundle-manifest"
DST_DIR="$ROOT/.opencode/scripts"
SRC_DIR="$ROOT/scripts"

PASS=0
FAIL=0

assert_pass() {
    local name="$1"
    echo "✓ $name"
    PASS=$((PASS + 1))
}

assert_fail() {
    local name="$1"
    local detail="${2:-}"
    echo "✗ $name${detail:+ — $detail}"
    FAIL=$((FAIL + 1))
}

require() {
    local name="$1"
    local path="$2"
    if [[ ! -e "$path" ]]; then
        echo "FATAL: falta $name: $path" >&2
        exit 2
    fi
}

require "scripts/build-local-snapshot.sh" "$SNAPSHOT"
require "scripts/.bundle-manifest"       "$MANIFEST"

# ──────────────────────────────────────────────────────────────────────────────
# Pre-checks: si el árbol real tiene drift, este test no puede correr positivo.
# ──────────────────────────────────────────────────────────────────────────────

if ! bash "$SNAPSHOT" --check >/dev/null 2>&1; then
    echo "WARN: el bundle real tiene drift; el test asume --check=0 sobre el árbol real." >&2
    echo "      Corré 'bash scripts/build-local-snapshot.sh --apply' antes de CI." >&2
    # No abortamos: los tests 1, 3, 4, 5 pueden no depender de estado real.
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 1: --check retorna 0 sobre el bundle real
# ──────────────────────────────────────────────────────────────────────────────

if bash "$SNAPSHOT" --check >/dev/null 2>&1; then
    assert_pass "build-local-snapshot.sh --check retorna 0 sobre árbol real"
else
    assert_fail "build-local-snapshot.sh --check retorna 0 sobre árbol real" \
        "rc=$? corré 'bash scripts/build-local-snapshot.sh --apply' para sincronizar"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 2: sin huérfanos en .opencode/scripts/ (whitelist del manifest)
# ──────────────────────────────────────────────────────────────────────────────

# Whitelist: dst_path en la col 2 del manifest (saltando header y comentarios).
whitelist="$(awk -F'\t' 'NR>1 && $1!~/^#/ && $2!="" {print $2}' "$MANIFEST" | sort -u)"
actual="$(find "$DST_DIR" -maxdepth 1 -type f ! -name '*.tmp*' -exec basename {} \; 2>/dev/null | sort)"
orphans="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$whitelist") || true)"
if [[ -z "$orphans" ]]; then
    assert_pass "sin huérfanos en .opencode/scripts/ ($(printf '%s\n' "$actual" | wc -l | tr -d ' ') archivos, todos en whitelist)"
else
    assert_fail "huérfanos detectados en .opencode/scripts/" \
        "$(printf '%s\n' "$orphans" | tr '\n' ' ')"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 3: drift detectado (en directorios aislados, no toca el árbol real)
# ──────────────────────────────────────────────────────────────────────────────

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src/scripts" "$TMP/dst/scripts"

# Armamos un mini-manifest con un único par. El manifest TSV tiene 4 columnas;
# las dos últimas (sha256_src, sha256_dst) son informativas; el script las ignora
# en --check y siempre recomputa. Por eso basta con strings vacíos.
{
    printf 'src_path\tdst_path\tsha256_src\tsha256_dst\n'
    printf 'src.txt\tdst.txt\t\t\n'
} > "$TMP/manifest.tsv"

# Crear src.txt y dst.txt idénticos -> check debe pasar
echo "hello world" > "$TMP/src/scripts/src.txt"
cp -p "$TMP/src/scripts/src.txt" "$TMP/dst/scripts/dst.txt"

if bash "$SNAPSHOT" --check \
        --manifest="$TMP/manifest.tsv" \
        --src="$TMP/src/scripts" \
        --dst="$TMP/dst/scripts" >/dev/null 2>&1; then
    assert_pass "drift-detection: --check pasa con bytes idénticos (isolated)"
else
    assert_fail "drift-detection: --check pasa con bytes idénticos (isolated)"
fi

# Ahora simulamos drift: dst.txt diverge byte a byte de src.txt.
# (El sleep fuerza mtime distinto; --check compara contenido, no mtime.)
sleep 1
echo "hello CHANGED" > "$TMP/dst/scripts/dst.txt"

if ! bash "$SNAPSHOT" --check \
        --manifest="$TMP/manifest.tsv" \
        --src="$TMP/src/scripts" \
        --dst="$TMP/dst/scripts" >/dev/null 2>&1; then
    assert_pass "drift-detection: --check retorna ≠0 tras divergencia de contenido"
else
    assert_fail "drift-detection: --check retorna ≠0 tras divergencia de contenido"
fi

# Drift por archivo faltante en dst
mkdir -p "$TMP/src2/scripts" "$TMP/dst2/scripts"
{
    printf 'src_path\tdst_path\tsha256_src\tsha256_dst\n'
    printf 'src.txt\tdst.txt\t\t\n'
} > "$TMP/manifest2.tsv"
echo "only in src" > "$TMP/src2/scripts/src.txt"
# No copiamos a dst2 -> --check debe reportar "dst falta".
if ! bash "$SNAPSHOT" --check \
        --manifest="$TMP/manifest2.tsv" \
        --src="$TMP/src2/scripts" \
        --dst="$TMP/dst2/scripts" >/dev/null 2>&1; then
    assert_pass "drift-detection: --check retorna ≠0 cuando dst falta"
else
    assert_fail "drift-detection: --check retorna ≠0 cuando dst falta"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 4: --apply es idempotente
# ──────────────────────────────────────────────────────────────────────────────

mkdir -p "$TMP/src3/scripts" "$TMP/dst3/scripts"
{
    printf 'src_path\tdst_path\tsha256_src\tsha256_dst\n'
    printf 'hi.txt\thi.txt\t\t\n'
} > "$TMP/manifest3.tsv"
echo "idempotent content" > "$TMP/src3/scripts/hi.txt"

# Primer apply
bash "$SNAPSHOT" --apply \
    --manifest="$TMP/manifest3.tsv" \
    --src="$TMP/src3/scripts" \
    --dst="$TMP/dst3/scripts" >/dev/null 2>&1

sha1_after_first="$(sha256sum < "$TMP/dst3/scripts/hi.txt" | awk '{print $1}')"

# Segundo apply: contenido idéntico, sha debe ser estable
bash "$SNAPSHOT" --apply \
    --manifest="$TMP/manifest3.tsv" \
    --src="$TMP/src3/scripts" \
    --dst="$TMP/dst3/scripts" >/dev/null 2>&1

sha1_after_second="$(sha256sum < "$TMP/dst3/scripts/hi.txt" | awk '{print $1}')"
if [[ -n "$sha1_after_second" && "$sha1_after_first" == "$sha1_after_second" ]]; then
    assert_pass "apply idempotente: --apply corrido N veces mantiene sha256"
else
    assert_fail "apply idempotente" "first=$sha1_after_first second=$sha1_after_second"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 5: --dry-run no escribe en el árbol real
# ──────────────────────────────────────────────────────────────────────────────

# Snapshot del estado antes
BEFORE_HASH="$(cd "$DST_DIR" && find . -type f ! -name '.*' -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | awk '{print $1}')"

bash "$SNAPSHOT" --dry-run >/dev/null 2>&1 || true

AFTER_HASH="$(cd "$DST_DIR" && find . -type f ! -name '.*' -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | awk '{print $1}')"
if [[ "$BEFORE_HASH" == "$AFTER_HASH" ]]; then
    assert_pass "dry-run no modifica el árbol (.opencode/scripts/ idéntico después)"
else
    assert_fail "dry-run no modifica el árbol" \
        "before=$BEFORE_HASH after=$AFTER_HASH"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 6: huérfano real vía --check (no la lógica duplicada del Test 2)
# Prueba el código de detección que vive DENTRO del script (el que corre el
# doctor/CI), no la copia de la lógica que hace este archivo de test.
# ──────────────────────────────────────────────────────────────────────────────

ORPHAN_FILE="$DST_DIR/.parity-orphan-probe.sh"
if [[ -e "$ORPHAN_FILE" ]]; then
    assert_fail "huérfano real vía --check (setup)" "archivo de prueba ya existía: $ORPHAN_FILE"
else
    echo '#!/usr/bin/env bash' > "$ORPHAN_FILE"
    ORPHAN_RC=0
    ORPHAN_OUT="$(bash "$SNAPSHOT" --check 2>&1)" || ORPHAN_RC=$?
    rm -f "$ORPHAN_FILE"  # lens:ok: literal DST_DIR + nombre fijo, nunca vacío
    CLEAN_RC=0
    bash "$SNAPSHOT" --check >/dev/null 2>&1 || CLEAN_RC=$?
    if [[ "$ORPHAN_RC" != "0" ]] && printf '%s' "$ORPHAN_OUT" | grep -q "huérfano"; then
        assert_pass "--check detecta huérfano inyectado y lo reporta"
    else
        assert_fail "--check detecta huérfano inyectado y lo reporta" \
            "rc=$ORPHAN_RC out=$(printf '%.200s' "$ORPHAN_OUT")"
    fi
    if [[ "$CLEAN_RC" == "0" ]]; then
        assert_pass "--check vuelve a pasar tras remover el huérfano"
    else
        assert_fail "--check vuelve a pasar tras remover el huérfano" "rc=$CLEAN_RC"
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 7: shellcheck --severity=warning sin errores
# ──────────────────────────────────────────────────────────────────────────────

if command -v shellcheck >/dev/null 2>&1; then
    SC_RC=0
    shellcheck --severity=warning "$SNAPSHOT" >/dev/null 2>&1 || SC_RC=$?
    if [[ "$SC_RC" == "0" ]]; then
        assert_pass "build-local-snapshot.sh shellcheck --severity=warning sin issues"
    else
        assert_fail "build-local-snapshot.sh shellcheck" "rc=$SC_RC"
    fi
else
    echo "· shellcheck no disponible; saltado"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Resumen
# ──────────────────────────────────────────────────────────────────────────────

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
