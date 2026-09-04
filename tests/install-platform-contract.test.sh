#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

# El preflight debe ser funcional: sin PATH, las dependencias esenciales fallan.
preflight_out="$({
  # shellcheck source=../scripts/lib/lib-os.sh
  source "$ROOT/scripts/lib/lib-os.sh"
  PATH=/directorio-que-no-existe skalling_require_dependencies
} 2>&1)"
preflight_rc=$?
assert "preflight rechaza dependencias ausentes" test "$preflight_rc" -ne 0
assert "preflight identifica sqlite3" grep -q "sqlite3" <<<"$preflight_out"
assert "preflight identifica python3" grep -q "python3" <<<"$preflight_out"

# El hash debe funcionar con la implementación portable del sistema.
hash_out="$(printf abc | {
  # shellcheck source=../scripts/lib/lib-os.sh
  source "$ROOT/scripts/lib/lib-os.sh"
  skalling_sha256_stream
})"
assert "sha256 portable produce el digest esperado" test "$hash_out" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
assert "instalador no depende directamente de sha256sum" sh -c "! grep -q 'sha256sum' '$ROOT/install-global.sh'"
assert "instalación global exige dependencias" grep -q 'skalling_require_dependencies' "$ROOT/install-global.sh"
assert "setup de proyecto exige dependencias" grep -q 'skalling_require_dependencies' "$ROOT/setup.sh"
assert "bootstrap exige dependencias" grep -q 'skalling_require_dependencies' "$ROOT/bootstrap-context.sh"
assert "doctor revisa sqlite3" grep -q 'command -v sqlite3' "$ROOT/setup-team-doctor.sh"
assert "doctor revisa python3" grep -q 'command -v python3' "$ROOT/setup-team-doctor.sh"

# Los wrappers PowerShell deben exponer opciones coherentes y distinguir runtimes.
assert "install-global.ps1 acepta SkallingDir" grep -q '\[string\]\$SkallingDir' "$ROOT/install-global.ps1"
assert "setup.ps1 acepta SkallingDir" grep -q '\[string\]\$SkallingDir' "$ROOT/setup.ps1"
assert "bootstrap-context.ps1 acepta SkallingDir" grep -q '\[string\]\$SkallingDir' "$ROOT/bootstrap-context.ps1"
assert "doctor.ps1 acepta SkallingDir" grep -q '\[string\]\$SkallingDir' "$ROOT/setup-team-doctor.ps1"
assert "setup.ps1 ofrece Uninstall" grep -q '\[switch\]\$Uninstall' "$ROOT/setup.ps1"
assert "wrapper Windows detecta wsl.exe" grep -q 'wsl.exe' "$ROOT/install-global.ps1"
assert "wrapper Windows usa cygpath para Git Bash" grep -q 'cygpath' "$ROOT/install-global.ps1"
assert "todos los wrappers distinguen WSL" sh -c "grep -q 'wsl.exe' '$ROOT/setup.ps1' && grep -q 'wsl.exe' '$ROOT/bootstrap-context.ps1' && grep -q 'wsl.exe' '$ROOT/setup-team-doctor.ps1'"

# CI debe ejecutar PowerShell de verdad y no fingir distintas versiones de Bash.
assert "CI ejecuta install-global.ps1 en Windows" grep -q 'install-global.ps1.*-DryRun' "$ROOT/.github/workflows/tests.yml"
assert "CI no declara una matriz Bash que no instala" sh -c "! grep -q 'bash-version:' '$ROOT/.github/workflows/tests.yml'"
assert "CI bloquea warnings de ShellCheck" grep -q 'shellcheck --severity=warning' "$ROOT/.github/workflows/tests.yml"
assert "README documenta dependencias esenciales" grep -q 'SQLite 3.*Python 3' "$ROOT/README.md"
assert "README diferencia Windows nativo de WSL" grep -q 'OpenCode dentro de WSL' "$ROOT/README.md"

# Una instalación global real debe quedar ejecutable, sin backup fantasma inicial.
install_root="$(mktemp -d)"
if HOME="$install_root" bash "$ROOT/install-global.sh" --force >/dev/null 2>&1; then
  assert "instalación real incluye lib-os para merge-helper" test -f "$install_root/.config/opencode/scripts/lib/lib-os.sh"
  assert "merge-helper instalado puede iniciar" env HOME="$install_root" bash "$install_root/.config/opencode/scripts/merge-helper.sh" --help
else
  fail "instalación global real"
fi

fresh_root="$(mktemp -d)"
if HOME="$fresh_root" bash "$ROOT/install-global.sh" >/dev/null 2>&1; then
  backup_count="$(find "$fresh_root/.config/opencode/.skalling-backups" -name 'opencode-*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')"
  assert "primera instalación no crea backup vacío" test "$backup_count" -eq 0
else
  fail "primera instalación global"
fi

space_project="$fresh_root/project with spaces"
mkdir -p "$space_project"
git -C "$space_project" init -q
printf '# Proyecto sin frontend\n' > "$space_project/README.md"
HOME="$fresh_root" bash "$ROOT/setup.sh" --target "$space_project" --force >/dev/null 2>&1
HOME="$fresh_root" bash "$ROOT/bootstrap-context.sh" --target "$space_project" --force >/dev/null 2>&1
doctor_out="$(HOME="$fresh_root" bash "$ROOT/setup-team-doctor.sh" --project "$space_project" 2>&1)"
if [[ "$doctor_out" != *"Concept doc huérfano"* ]]; then pass "doctor preserva rutas con espacios"; else fail "doctor preserva rutas con espacios"; fi
if [[ "$doctor_out" != *"Frontend detectado"* ]]; then pass "doctor no inventa frontend desde placeholders"; else fail "doctor no inventa frontend desde placeholders"; fi

printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
