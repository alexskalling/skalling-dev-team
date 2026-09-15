#!/usr/bin/env bash
# tests/skills-shared-references.test.sh — ninguna skill referencia un archivo
# skills/_shared/*.md que no existe, y las 10 skills sdd-* + _shared quedan
# instaladas (antes ni siquiera estaban en el catálogo core: código
# completamente inalcanzable, ninguna sesión real podía cargarlas).
#
# Contexto (2026-09-14, proyecto Survan en vivo): un agente escribió
# "mkdir -p .opencode/plans/<slug> && cat > tasks.md" -- el patrón legacy que
# ya se había prohibido en Sol.md/Teo.md (ver test_tier1_fixes en
# setup.test.sh). Al investigar se encontraron dos bugs reales distintos: (1)
# las skills sdd-* (importadas de gentleman-programming) referenciaban 4
# archivos skills/_shared/*.md que nunca existieron, y (2) esas mismas skills
# nunca estuvieron en data/skills-by-stack.yaml → install-global.sh jamás las
# instalaba, en ningún proyecto. El incidente en sí probablemente no vino de
# esa skill (no estaba cargada), pero ambos bugs eran reales y quedaban sin
# detectar -- este test cubre los dos de una vez.
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

# Las skills sdd-* + _shared tienen que estar en el catálogo core, si no
# install-global.sh nunca las copia a ningún lado -- exactamente el segundo
# bug real que encontramos: código completo, correcto, e inalcanzable.
CORE_SKILLS="$(source "$ROOT/scripts/lib/lib-stack-detect.sh" && skalling_core_skills "$ROOT/data/skills-by-stack.yaml")"
for name in _shared sdd-init sdd-explore sdd-propose sdd-spec sdd-design sdd-tasks sdd-apply sdd-verify sdd-archive sdd-onboard; do
  if grep -qx "$name" <<< "$CORE_SKILLS"; then
    assert_pass "$name está en el catálogo core (skills-by-stack.yaml)"
  else
    assert_fail "$name está en el catálogo core (skills-by-stack.yaml)"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
