#!/usr/bin/env bash
# /skalling-init (bootstrap --install-project) deja el proyecto igual que
# setup.sh, y los controles se activan aunque el contexto esté "degradado".
# Antes: init solo creaba la memoria, y en un proyecto casi vacío cortaba sin
# hooks y con el agente nativo `build` por defecto (auditoría 2026-09-27).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then echo "✓ $1"; PASS=$((PASS+1)); else echo "✗ $1" >&2; FAIL=$((FAIL+1)); fi; }

export HOME="$TMP/home" SKALLING_OPENCODE_DIR="$TMP/home/.config/opencode"
mkdir -p "$HOME"
bash "$ROOT/install-global.sh" >/dev/null 2>&1
check "install-global registra el checkout fuente" \
  '[ "$(cat "$SKALLING_OPENCODE_DIR/skalling-data/source-dir")" = "$ROOT" ]'

P="$TMP/p"
mkdir -p "$P"
git -C "$P" init -q
echo '{"name":"p","scripts":{"test":"node --test"}}' > "$P/package.json"
rc=0
bash "$SKALLING_OPENCODE_DIR/bootstrap-context.sh" --target "$P" --install-project >/dev/null 2>&1 || rc=$?
check "proyecto casi vacío: bootstrap avisa contexto incompleto (exit 3)" '[ "$rc" -eq 3 ]'
check "agentes instalados en el proyecto" '[ "$(ls "$P/.opencode/agents"/*.md | wc -l | tr -d " ")" -eq 8 ]'
check "plugins instalados en el proyecto" '[ -f "$P/.opencode/plugins/skalling-git-guard.js" ]'
check "aprobador humano instalado en el proyecto" '[ -f "$P/.opencode/scripts/skalling-approve.sh" ]'
check "hook pre-commit activo aunque el contexto esté degradado" '[ -e "$P/.git/hooks/pre-commit" ]'
check "Alex por defecto aunque el contexto esté degradado" 'grep -q "\"default_agent\": \"Alex\"" "$P/.opencode/opencode.json"'

Q="$TMP/q"
mkdir -p "$Q"
git -C "$Q" init -q
echo '{"name":"q"}' > "$Q/package.json"
bash "$SKALLING_OPENCODE_DIR/bootstrap-context.sh" --target "$Q" >/dev/null 2>&1 || true
check "sin --install-project no copia agentes al proyecto" '[ ! -d "$Q/.opencode/agents" ]'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
