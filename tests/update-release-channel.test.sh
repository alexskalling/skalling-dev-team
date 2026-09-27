#!/usr/bin/env bash
# update.sh instala releases publicados (tags vX.Y.Z), nunca el último push a
# main, y vuelve a la versión anterior si la instalación falla.
# Auditoría 2026-09-27: antes hacía "git pull origin main" sin más.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { local name="$1"; shift; if "$@"; then echo "  ✓ $name"; PASS=$((PASS+1)); else echo "  ✗ $name"; FAIL=$((FAIL+1)); fi; }

g() { git -c user.email=t@example.test -c user.name=t -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

SRC="$TMP/src"; mkdir -p "$SRC/scripts"
g init -q -b main "$SRC"
cp "$ROOT/scripts/update.sh" "$SRC/scripts/update.sh"
cat > "$SRC/install-global.sh" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_INSTALL_FAIL:-0}" = "1" ] && exit 1
git rev-parse HEAD > "$HOME/installed"
EOF
echo "# v1" > "$SRC/CHANGELOG.md"
g -C "$SRC" add -A && g -C "$SRC" commit -qm v1 && g -C "$SRC" tag v1.0.0
g clone -q "$SRC" "$TMP/clone" 2>/dev/null
g -C "$TMP/clone" checkout -q v1.0.0 2>/dev/null
export HOME="$TMP/home"; mkdir -p "$HOME"
run() { bash "$TMP/clone/scripts/update.sh" --repo "$TMP/clone" "$@"; }

echo "wip" >> "$SRC/CHANGELOG.md"; g -C "$SRC" commit -qam "trabajo sin publicar"
out="$(run --check-only 2>&1)"
check "sin release nuevo, un push a main no se ofrece" grep -q "Ya estás en la última versión (v1.0.0)" <<<"$out"

g -C "$SRC" tag v1.1.0
echo "más wip" >> "$SRC/CHANGELOG.md"; g -C "$SRC" commit -qam "posterior al release"
out="$(run --check-only 2>&1)"
check "detecta el release nuevo" grep -q "v1.1.0 trae" <<<"$out"

out="$(echo s | run 2>&1)"
check "instala exactamente el tag, no main" [ "$(g -C "$TMP/clone" rev-parse HEAD)" = "$(g -C "$SRC" rev-parse 'v1.1.0^{commit}')" ]
check "el instalador corrió sobre el release" [ "$(cat "$HOME/installed")" = "$(g -C "$SRC" rev-parse 'v1.1.0^{commit}')" ]

g -C "$SRC" tag v1.2.0
before="$(g -C "$TMP/clone" rev-parse HEAD)"
out="$(echo s | FAKE_INSTALL_FAIL=1 run 2>&1)"; rc=$?
check "instalación fallida devuelve error" [ "$rc" -ne 0 ]
check "instalación fallida vuelve a la versión anterior" [ "$(g -C "$TMP/clone" rev-parse HEAD)" = "$before" ]

g -C "$SRC" tag -d v1.0.0 v1.1.0 v1.2.0 >/dev/null
rm -rf "$TMP/clone2"; g clone -q --no-tags "$SRC" "$TMP/clone2" 2>/dev/null
out="$(bash "$TMP/clone2/scripts/update.sh" --repo "$TMP/clone2" --check-only 2>&1)"; rc=$?
check "sin releases publicados no instala nada" [ "$rc" -ne 0 ]
check "explica que faltan releases" grep -q "No hay releases publicados" <<<"$out"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
