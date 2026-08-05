---
description: Help resolve merge conflicts in Skalling memory bundle (.opencode/). Trigger: git merge conflict, "merge conflict in OKF", "two devs edited same file", "concurrency in memory".
---

# Skalling Merge

Asiste en la resolución de conflictos en archivos del bundle OKF (`.opencode/`) cuando dos devs mergearon cambios que se solapan.

## Cuándo activarme

- Hay un git merge en curso con conflictos en `.opencode/**`.
- Alguien pregunta "¿cómo resuelvo este conflicto en el bundle?".
- Vas a mergear un PR que toca `.opencode/` y querés prevenir conflictos.
- Dos features en paralelo escribieron en el mismo concept doc.

## Protocolo

### Paso 1 — Detectar conflictos

Llamá al helper script:

```bash
bash ~/skalling-dev-team/scripts/merge-helper.sh
```

El script detecta:
- Archivos `.opencode/` en estado de conflicto git (`<<<<<<<`, `=======`, `>>>>>>>`).
- Colisiones de nombres entre branches (mismo `YYYY-MM-DD-titulo.md` creado por dos devs).
- Conflictos en archivos protegidos (workflow.json, constitución).

Para cada conflicto, da **una sugerencia concreta** según el tipo de archivo.

### Paso 2 — Entender el protocolo por tipo

| Archivo | Estrategia git | Resolución típica |
|---|---|---|
| `context/log.md` | `merge=union` (auto si .gitattributes OK) | Conservar ambas entradas, deduplicar si es necesario |
| `context/index.md` | `merge=union` | Regenerar con `/skalling-refresh` |
| `context/constitucion.md` | `merge=lock` | Escalar al equipo, decisión colectiva |
| `state/workflow.json` | `merge=lock` | Decidir quién continúa el ciclo |
| `decisiones/<file>.md` | Manual | Leer ambas versiones, quedarse con la más completa o renombrar |
| `trabajo-en-curso/<file>.md` | Manual | Serializar trabajo o renombrar |
| `stack/<file>.md` | Manual o union | Considerar ignorar en git (es auto-regenerable) |
| `proyecto/<file>.md` | Manual | Mergear conceptualmente |
| `preferencias/<file>.md` | Manual | Escalar (preferencias son colectivas) |
| `problemas-conocidos/<file>.md` | Manual | Mantener ambos o decidir el mejor |
| `changes/<feature>/proposal.md` | Manual | Serializar el feature |
| `changes/<feature>/design.md` | Manual | Serializar el feature |
| `changes/<feature>/tasks.md` | Manual | Reorganizar tasks por owner |
| `project.yaml` | `merge=union` | Regenerar con `/skalling-refresh` |

### Paso 3 — Aplicar resolución

#### Para conflictos "duros" (mismo archivo, distinto contenido)

1. **NO aceptar el ours/theirs automáticamente** — leé las dos versiones.
2. **Si son la misma idea con distinto wording**: elegí la más completa y agregá `supersedes:` linkeando a la otra.
3. **Si son ideas distintas**: mergear conceptualmente, no copy-paste.
4. **Si son contradictorias**: NO resolver acá. Escalar al equipo con:
   - Ambas versiones citadas.
   - Pregunta concreta de qué gana.
   - Plazo para decidir.

#### Para conflicts "soft" (auto-resolubles)

- `log.md`, `index.md`, `project.yaml` con `merge=union`: ya están resueltos por git. Solo verificar que no haya duplicados lógicos.
- `index.md` regenerable: borrar y correr `/skalling-refresh`.
- `project.yaml`: regenerar con `bash bootstrap-context.sh --force`.

### Paso 4 — Documentar la resolución

Después de resolver, append al `log.md`:

```markdown
## YYYY-MM-DD HH:MM — Resolución de merge conflict
**Por:** pau (con asistencia de alex)
**Conflicto en:** [archivo(s)]
**Resolución:** [qué se decidió]
**Razón:** [por qué se eligió esta versión]
```

Esto deja registro histórico de cómo se resolvieron los conflictos.

### Paso 5 — Prevenir futuros conflictos

#### Recomendación 1: Un feature por branch

Si dos devs trabajan en features distintas, branches separadas minimizan conflictos en `decisiones/`, `trabajo-en-curso/`, etc.

#### Recomendación 2: Nombres únicos para ADRs

Cuando Pol propone una decisión, el filename debe incluir un sufijo único. Patrón recomendado:
```
YYYY-MM-DD-titulo-corto-autor-iniciales.md
# Ejemplo: 2026-07-28-elegir-postgres-JPM.md
```

Si dos devs crean `<mismo-nombre>.md`, hay conflicto. Con sufijo de autor, no.

#### Recomendación 3: Lock del ciclo activo

`workflow.json` con `merge=lock` evita que dos ciclos corran en paralelo. Si dos devs inician ciclo simultáneo:
- El segundo debe esperar a que el primero termine.
- O el primero aborta y deja que el segundo tome.

#### Recomendación 4: Git worktrees para features grandes

```bash
git worktree add ../mi-feature-auth feat/auth
cd ../mi-feature-auth
# Trabajar en aislamiento
# Al terminar:
cd ../mi-proyecto-original
git merge feat/auth
```

Cada worktree tiene su propio filesystem. Los conflictos se resuelven al mergear, no durante el trabajo.

## Anti-patrones

- ❌ **Auto-aceptar ours/theirs sin leer** — pérdida silenciosa de información.
- ❌ **Hacer merge de `--force`** — destruye trabajo del otro dev.
- ❌ **Modificar constitución sin acuerdo** — la constitución es colectiva.
- ❌ **Crear dos decisiones con mismo nombre** — usar sufijos únicos.
- ❌ **Trabajar dos devs en mismo feature sin coordinación** — serializar.

## Si el conflicto es irresoluble

1. Escalar al usuario con resumen del bloqueo.
2. Listar las dos versiones lado a lado.
3. Pedir decisión con opciones.
4. Aplicar la decisión con commit claro: `merge: resolver conflicto entre feature-X y feature-Y`.

## Cuándo NO activarme

- Si el conflicto NO está en `.opencode/` (es código regular, no me meto).
- Si el usuario sabe resolverlo y solo necesita confirmación (doy OK y me retiro).
- Si es un merge trivial sin solapamiento (lo señalo y termino).

## TeamDB

Si hay conflictos en `.sql` files de teamdb:

```bash
# Ver archivos en conflicto
git status | grep teamdb

# Aplicar estrategia union (mantiene ambos lados)
git checkout --union .opencode/context/teamdb/data_*.sql

# Reimportar
bash scripts/teamdb-import.sh .
```

Si el union no resuelve, editá el `.sql` manualmente y reimportá.
