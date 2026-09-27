#!/usr/bin/env bash
# Matriz de soporte de OpenCode (lib-os.sh) y timeout de los corredores.
# No prueba el binario real de OpenCode: solo la clasificación de versiones y
# la detección del SDK de plugins que escribe OpenCode en .opencode/.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name (esperado '$want', obtenido '$got')"; fi
}

# shellcheck source=../scripts/lib/lib-os.sh
source "$ROOT/scripts/lib/lib-os.sh"
# shellcheck source=lib/with-timeout.sh
source "$ROOT/tests/lib/with-timeout.sh"

# ── Clasificación de la salida de `opencode --version` ──
assert_eq "1.18.28 no soportada" unsupported "$(skalling_opencode_support "1.18.28")"
assert_eq "1.18.29 es v1 (mínimo exacto)" v1 "$(skalling_opencode_support "1.18.29")"
assert_eq "1.19.0 es v1" v1 "$(skalling_opencode_support "1.19.0")"
assert_eq "0.9.9 no soportada" unsupported "$(skalling_opencode_support "0.9.9")"
assert_eq "'opencode v2.0.18' es v2" v2 "$(skalling_opencode_support "opencode v2.0.18")"
assert_eq "salida vacía es unknown" unknown "$(skalling_opencode_support "")"
assert_eq "salida sin semver es unknown" unknown "$(skalling_opencode_support "Error: EACCES log")"

# ── SDK de plugins (@opencode-ai/plugin) instalado por OpenCode ──
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_eq "sin package.json ni node_modules: absent" "absent	" "$(skalling_plugin_pkg_status "$tmp/nada")"

mkdir -p "$tmp/decl"
printf '{\n  "dependencies": {\n    "@opencode-ai/plugin": "1.18.18"\n  }\n}\n' > "$tmp/decl/package.json"
assert_eq "declarada 1.18.18 (bajo el mínimo): old" "old	1.18.18" "$(skalling_plugin_pkg_status "$tmp/decl")"

# La versión instalada manda sobre la declarada.
mkdir -p "$tmp/decl/node_modules/@opencode-ai/plugin"
printf '{\n  "name": "@opencode-ai/plugin",\n  "version": "1.18.30"\n}\n' > "$tmp/decl/node_modules/@opencode-ai/plugin/package.json"
assert_eq "instalada 1.18.30 manda sobre la declarada" "ok	1.18.30" "$(skalling_plugin_pkg_status "$tmp/decl")"

mkdir -p "$tmp/rango"
printf '{ "dependencies": { "@opencode-ai/plugin": "latest" } }\n' > "$tmp/rango/package.json"
assert_eq "rango no numérico: unknown" "unknown	latest" "$(skalling_plugin_pkg_status "$tmp/rango")"

# ── Timeout portable ──
skalling_with_timeout 5 bash -c 'exit 7'
assert_eq "timeout propaga el código de salida" 7 "$?"
skalling_with_timeout 1 bash -c 'sleep 20' 2>/dev/null
assert_eq "timeout vencido sale con 124" 124 "$?"

printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
