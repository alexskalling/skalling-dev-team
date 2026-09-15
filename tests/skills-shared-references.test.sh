#!/usr/bin/env bash
# tests/skills-shared-references.test.sh — ninguna skill referencia un archivo
# skills/_shared/*.md que no existe.
#
# Bug real (2026-09-14, proyecto Survan en vivo): las 9 skills sdd-* (importadas
# de gentleman-programming) referenciaban skills/_shared/sdd-phase-common.md y
# skills/_shared/openspec-convention.md -- archivos que NUNCA existieron en el
# repo. Sol, sin la Sección C (persistencia) que ese archivo faltante debía
# darle, termino haciendo "mkdir -p .opencode/plans/<slug> && cat > tasks.md"
# -- exactamente el patron legacy que ya se habia prohibido en Sol.md/Teo.md
# (ver test_tier1_fixes en setup.test.sh) pero que volvio a colarse por una
# via distinta sin que nada lo detectara.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

MISSING=0
for skill_file in "$ROOT"/skills-base/*/SKILL.md; do
  refs="$(grep -oE '(skills/_shared|\.\./_shared)/[a-zA-Z0-9._-]+\.md' "$skill_file" | sort -u || true)"
  [ -n "$refs" ] || continue
  while IFS= read -r ref; do
    name="$(basename "$ref")"
    if [ ! -f "$ROOT/skills-base/_shared/$name" ]; then
      assert_fail "referencia rota en $(basename "$(dirname "$skill_file")")/SKILL.md" "apunta a _shared/$name, que no existe"
      MISSING=$((MISSING + 1))
    fi
  done <<< "$refs"
done

if [ "$MISSING" -eq 0 ]; then
  assert_pass "todas las referencias a skills/_shared/*.md en skills-base/*/SKILL.md resuelven a un archivo real"
fi

for f in sdd-phase-common.md openspec-convention.md; do
  if [ -f "$ROOT/skills-base/_shared/$f" ]; then
    assert_pass "skills-base/_shared/$f existe"
  else
    assert_fail "skills-base/_shared/$f existe"
  fi
  if [ -f "$ROOT/.opencode/skills/_shared/$f" ]; then
    assert_pass ".opencode/skills/_shared/$f existe (mirror instalado)"
  else
    assert_fail ".opencode/skills/_shared/$f existe (mirror instalado)"
  fi
  if diff -q "$ROOT/skills-base/_shared/$f" "$ROOT/.opencode/skills/_shared/$f" >/dev/null 2>&1; then
    assert_pass "$f: skills-base y .opencode/skills coinciden"
  else
    assert_fail "$f: skills-base y .opencode/skills coinciden"
  fi
done

# El fix de fondo: la fuente de verdad tiene que decir explícitamente que
# nunca se escribe a .opencode/plans/ -- no alcanza con que el archivo exista,
# tiene que decir lo correcto.
if grep -q "opencode/plans" "$ROOT/skills-base/_shared/sdd-phase-common.md"; then
  assert_pass "sdd-phase-common.md prohíbe explícitamente escribir en .opencode/plans/"
else
  assert_fail "sdd-phase-common.md prohíbe explícitamente escribir en .opencode/plans/"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
