#!/usr/bin/env bash
# setup.sh --with-ci instala la capa autoritativa (workflow de CI + CODEOWNERS)
# sin pisar lo que el proyecto ya tenga. Auditoría 2026-09-27: los proyectos
# no recibían ninguna CI que re-verifique fuera del checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
check "el workflow es YAML válido" 'python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP/p/.github/workflows/skalling-verify.yml"'
check "el workflow lee el comando de project.yaml" '(cd "$TMP/p" && [ -n "$(PYTHONPATH=.opencode/scripts python3 -m skalling_config .opencode/project.yaml unit)" ])'

echo "# propio" > "$TMP/p/.github/workflows/skalling-verify.yml"
echo "* @equipo" > "$TMP/p/.github/CODEOWNERS"
bash "$ROOT/setup.sh" --target "$TMP/p" --force --with-ci >/dev/null 2>&1
check "no pisa un workflow existente" 'grep -qx "# propio" "$TMP/p/.github/workflows/skalling-verify.yml"'
check "no pisa un CODEOWNERS existente" 'grep -qx "\* @equipo" "$TMP/p/.github/CODEOWNERS"'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
