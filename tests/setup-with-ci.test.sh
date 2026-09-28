#!/usr/bin/env bash
# setup.sh --with-ci instala la capa autoritativa (workflow de CI + CODEOWNERS)
# sin pisar lo que el proyecto ya tenga. Auditoría 2026-09-27: los proyectos
# no recibían ninguna CI que re-verifique fuera del checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Misma resolucion de Python y misma guarda de dependencias que tests/run-all.sh
# (lineas 12-21): este test valida YAML y corre skalling_config, asi que una
# dependencia faltante es un FALLO con mensaje claro, no un ModuleNotFoundError
# en mitad de un assert. Una dependencia faltante es un fallo, no un salto.
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if [ -x "$ROOT/.venv/bin/python" ]; then PY="$ROOT/.venv/bin/python"; else PY="python3"; fi
fi
if ! "$PY" -c 'import jsonschema, yaml' 2>/dev/null; then
  echo "FALLO: $PY no tiene jsonschema/pyyaml (python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml)" >&2
  exit 1
fi
# Los asserts invocan python por $PY (no por el python3 del PATH).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then echo "✓ $1"; PASS=$((PASS+1)); else echo "✗ $1" >&2; FAIL=$((FAIL+1)); fi; }

export HOME="$TMP/home" SKALLING_OPENCODE_DIR="$TMP/home/.config/opencode"
mkdir -p "$HOME" "$TMP/p"
git -C "$TMP/p" init -q
echo '{"name":"p","scripts":{"test":"node --test"}}' > "$TMP/p/package.json"

# Flujo real: bootstrap (crea project.yaml; exit 3 = contexto aún no hidratado) y setup.
bash "$ROOT/bootstrap-context.sh" --target "$TMP/p" --force >/dev/null 2>&1 || [ $? -eq 3 ]
bash "$ROOT/setup.sh" --target "$TMP/p" --force >/dev/null 2>&1
check "sin --with-ci no se crea .github/" '[ ! -e "$TMP/p/.github" ]'

bash "$ROOT/setup.sh" --target "$TMP/p" --force --with-ci >/dev/null 2>&1
check "workflow instalado" '[ -f "$TMP/p/.github/workflows/skalling-verify.yml" ]'
check "CODEOWNERS instalado" 'grep -q "/.opencode/" "$TMP/p/.github/CODEOWNERS"'
check "el workflow es YAML válido" '"$PY" -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP/p/.github/workflows/skalling-verify.yml"'
check "el workflow lee el comando de project.yaml" '(cd "$TMP/p" && [ -n "$(PYTHONPATH=.opencode/scripts "$PY" -m skalling_config .opencode/project.yaml unit)" ])'

echo "# propio" > "$TMP/p/.github/workflows/skalling-verify.yml"
echo "* @equipo" > "$TMP/p/.github/CODEOWNERS"
bash "$ROOT/setup.sh" --target "$TMP/p" --force --with-ci >/dev/null 2>&1
check "no pisa un workflow existente" 'grep -qx "# propio" "$TMP/p/.github/workflows/skalling-verify.yml"'
check "no pisa un CODEOWNERS existente" 'grep -qx "\* @equipo" "$TMP/p/.github/CODEOWNERS"'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
