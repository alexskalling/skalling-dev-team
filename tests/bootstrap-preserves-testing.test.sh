#!/usr/bin/env bash
# tests/bootstrap-preserves-testing.test.sh — /skalling-init --force regenera
# project.yaml pero conserva la configuración de tests que puso una persona.
#
# Encontrado al actualizar una instalación real (27-09-2026): --force copiaba la
# plantilla encima y reescribía testing con lo detectado (nada, en un repo sin
# package.json). Jhon y la verificación automática quedaban sin comando.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/src" "$TMP/.opencode"
printf 'print(1)\n' > "$TMP/src/app.py"
git -C "$TMP" init -q
bash "$ROOT/bootstrap-context.sh" --target "$TMP" >/dev/null 2>&1 || true
cat > "$TMP/.opencode/project.yaml" <<'YAML'
testing:
  timeout_seconds: 1200
  unit:
    available: true
    command: "python3 -m pytest -q"
  fast:
    available: true
    command: "python3 -m pytest -q {files}"
YAML
bash "$ROOT/bootstrap-context.sh" --target "$TMP" --force >/dev/null 2>&1 || true
YAML="$TMP/.opencode/project.yaml"
grep -q 'schema: skalling-project-v1' "$YAML" || { echo "✗ no regeneró project.yaml" >&2; exit 1; }
grep -q 'command: "python3 -m pytest -q"' "$YAML" || { echo "✗ perdió testing.unit" >&2; exit 1; }
grep -q 'command: "python3 -m pytest -q {files}"' "$YAML" || { echo "✗ perdió testing.fast" >&2; exit 1; }
grep -q 'timeout_seconds: 1200' "$YAML" || { echo "✗ perdió timeout_seconds" >&2; exit 1; }
[ ! -f "$TMP/.opencode/project.yaml.previous" ] || { echo "✗ quedó project.yaml.previous" >&2; exit 1; }
echo "PASS: --force regenera project.yaml y conserva comandos de tests y timeout"
