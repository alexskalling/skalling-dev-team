# AGENTS.md — Índice de Skalling para este proyecto

Este proyecto usa [Skalling](https://github.com/tu-usuario/skalling-dev-team). El equipo agentico completo (Alex + 7 especialistas) vive en `.opencode/agents/`.

## Reglas Universales

Ver `.opencode/context/constitucion.md` (o `~/.config/opencode/constitucion.md`).

## Skills Disponibles

| Skill | Trigger |
|---|---|
| `skalling-tdd` | Implementar lógica con TDD (red-green-refactor) |
| `skalling-debug` | Debugging sistemático |
| `skalling-verify` | Antes de declarar completo, verificar |
| `skalling-planning` | Escribir planes de implementación |
| `skalling-code-review` | Code review excellence |
| `skalling-doc-coauthoring` | Co-escribir documentación |
| `skalling-brainstorming` | Lluvia de ideas estructurada |
| `skalling-find-skills` | Buscar skills adicionales |

## Comandos

- `/skalling-init` — bootstrap del proyecto
- `/skalling-status` — ver estado de memoria
- `/skalling-refresh` — re-detectar stack
- `/skalling-doctor` — health check
- `/skalling-memory` — buscar, relacionar y revisar memoria
- `/skalling-resume` — retomar trabajo con contexto mínimo
- `/skalling-recover` — recuperar TeamDB con backup

## Bundle local `.opencode/scripts/`

El repo mantiene dos copias paralelas de los scripts: la canónica en
`scripts/` (source of truth) y una aplanada en `.opencode/scripts/`
(usada como `SKALLING_ROOT/scripts/` cuando se invoca dentro de este
proyecto). La aplanización `lib/` → `lib-*` evita que `source` resuelva
rutas distintas.

**Contrato** (definido en `scripts/.bundle-manifest`, TSV):
- `scripts/{skalling-*,teamdb-*}.[sh|py]` y un conjunto explícito de
  utilidades → `.opencode/scripts/<name>` 1:1.
- `scripts/lib/lib-{os,stack-detect,teamdb}.sh` →
  `.opencode/scripts/lib-{os,stack-detect,teamdb}.sh` (aplanizado).
- Ignorados: `__pycache__/`, `hooks/`, `lib/lib-memory-check.sh` (helper
  sourced), `render-agent.sh`, `permission-policy.py`, `migrate-*`,
  `test-teamdb-*`.

**Regenerar / verificar:**
```bash
bash scripts/build-local-snapshot.sh --apply   # copia src → dst (atómico, cp -p)
bash scripts/build-local-snapshot.sh --check   # exit 0 si sin drift
bash scripts/build-local-snapshot.sh --dry-run # imprime plan sin tocar nada
```

Aceptan `--manifest=<path>`, `--src=<path>`, `--dst=<path>` para overrides.

**Drift = problem.** Si `--check` retorna ≠0, los agentes que leen
`scripts/` y `.opencode/scripts/` pueden ver versiones divergentes.
Soluciones:
1. Regenerá con `--apply`.
2. `bash setup-team-doctor.sh` lo reporta como WARNING; `--strict` lo
   promueve a error.
3. `bash tests/scripts-parity.test.sh` se ejecuta en CI y es gate de
   push a `main`/`develop` y de PRs a `main` (ver
   `.github/workflows/tests.yml`).

## Memoria

Bundle OKF en `.opencode/context/`. Cada concept doc tiene frontmatter YAML.

## Hooks (separación de scopes)

Los hooks de Git tienen scopes DIFERENTES por diseño:

- **`scripts/hooks/git-gate.py`** (pre-commit + pre-push) — corre cosas RÁPIDAS
  contra el candidato exacto (staged/published diff):
  - Detección de secretos hardcodeados (regex sobre el diff).
  - Coherencia memoria ↔ repo (cada `.md` bajo `.opencode/context/` debe tener
    fila en TeamDB; falla si no).
  - Verificación de receipt sellado (cada commit debe tener un `tree_hash` con
    exit_code=0 en `receipts`; sin fabricar comprobantes).
  - **NO** corre el linter SQLi: demasiado lento (escanea `scripts/**` entero)
    y fuera de scope del gate pre-push (que valida el candidato exacto).

- **`.github/workflows/lint-sqli.yml`** (push + PR) — gate CI BLOQUEANTE
  del linter SQLi (`scripts/skalling-review.sh --lens risk --scope 'scripts/**'`
  con exclusiones documentadas). Cubre variables interpoladas sin escapar
  dentro de una query `sqlite3` (comilla simple o doble), que es lo que el
  pre-push no valida.

Razón de la separación: el pre-push necesita ser barato (~ms) porque se ejecuta
en CADA push; un linter estático que escanea todo `scripts/**` toma segundos y
no aporta bloquear el push individual (los archivos ya están commiteados). El
CI corre el linter en push/PR a `main` y `develop`, que es donde importa la
calidad acumulada del repo.

Si un nuevo check es rápido Y aplica al candidato → pre-push. Si es lento O
escaneo completo → CI workflow. No duplicar.
