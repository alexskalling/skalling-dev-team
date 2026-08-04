# Proposal: Spec ↔ Memory link — trazabilidad de concept docs a planes archivados

> **Status**: Approved
> **Author**: Pol
> **Created**: 2026-08-04
> **Approved**: 2026-08-04 (scope confirmado por el usuario)

## Why

Cuando Pau archiva un plan que creó o modificó concept docs en `.opencode/context/concept/`, **no queda ningún link desde el concept doc hacia la spec original que justificó la decisión**. Los síntomas concretos:

1. **Decisiones no trazables.** Si dentro de 6 meses alguien lee un concept doc tipo *"usamos repository pattern para DB"*, no puede llegar fácilmente a la spec que justificó esa elección. Tiene que abrir cada plan archivado y cruzar a mano.
2. **Specs huérfanas en su origen.** Los planes archivados dicen "esta feature modificó concept docs X, Y, Z", pero los concept docs no devuelven el favor. La trazabilidad es unidireccional y se pierde en el tiempo.
3. **Memoria que pierde valor.** El bundle OKF (`.opencode/context/`) es el activo de memoria de Skalling. Que una decisión no apunte a su evidencia es un agujero de calidad que hoy nadie detecta porque no hay un link que falte.

El MVP no intenta arreglar la trazabilidad end-to-end (eso es el flujo inverso, Open Spec completo). Solo **una flecha mínima**: del concept doc hacia la spec que lo justificó, escrita en el momento del archivado.

## What Changes

Un MVP pequeño, idempotente y portable, compuesto por:

1. **Script Bash nuevo** `scripts/spec-memory-link.sh` (helper de Pau) que, dado el directorio de un plan a archivar, detecta qué concept docs affected y les agrega un footer `## Spec original`.
2. **Detección por path literal.** El script busca paths a `.opencode/context/concept/*.md` dentro de `proposal.md`, `design.md`, `tasks.md` y `specs/*.md` del plan. Deduplica los matches.
3. **Footer estándar.** Para cada concept doc afectado, agrega al final del archivo una sección:
   ```markdown
   ## Spec original

   [.opencode/changes/archive/<YYYY-MM>/<slug>/](.opencode/changes/archive/<YYYY-MM>/<slug>/)
   ```
   El link es **relativo al concept doc** (no absoluto), y apunta al path FINAL post-archivado (Pau calcula la fecha de archive y la usa).
4. **Idempotencia.** Si el concept doc ya tiene `## Spec original`, NO se sobrescribe. Se preserva el primero. Esto evita perder evidencia histórica cuando varios planes tocan el mismo concept doc.
5. **Pau PASO 5 modificado.** Pau, en su paso de archivado, ejecuta el script antes de mover la carpeta a `archive/`. El script ya recibe el path final del destino.
6. **Tests Bash** en `tests/spec-memory-link.test.sh` con fixtures temporales, cobertura de éxito, fallo, idempotencia y edge cases.
7. **Sección informativa en doctor.** `setup-team-doctor.sh` informa la disponibilidad del script con `ℹ` azul, no la ejecuta automáticamente, no modifica su exit code y no convierte findings en warnings.
8. **Claims verificables.** Cada spec lleva sección `## Verificación` con claims `- archivo:` / `- contiene:` / `- count:` para que `scripts/skalling-drift.sh` valide el cambio cuando se archive.

El script es portable con Bash 3.2, no usa `declare -A`, `mapfile` ni `readarray`, y depende solo de `find`, `grep`, `sed`, `awk` y `dirname`. Identificadores en español (R1), cero comentarios en código (R2), commits en español (R16).

## Impact

Archivos previstos:

- **`scripts/spec-memory-link.sh`** — nuevo CLI Bash. Detecta concept docs afectados, agrega footer, idempotente.
- **`agents-base/Pau.md`** — sección PASO 5 extendida con invocación al script antes de mover la carpeta. Permisos ya existentes (`edit: .opencode/context/**/*.md: allow`, `edit: .opencode/changes/**: allow`, `bash: "*": ask` que ya cubre cualquier invocación). NO se rompe nada del flujo actual.
- **`tests/spec-memory-link.test.sh`** — nuevo test suite Bash siguiendo el patrón de `tests/concept-template.test.sh` y `tests/skalling-drift.test.sh`.
- **`setup-team-doctor.sh`** — nueva línea informativa `ℹ` sobre la disponibilidad del script, sin afectar contadores ni exit code.
- **`command/skalling-doctor.md`** — documentación de la nueva sección informativa.

NO se tocan:

- `constitution/constitucion.md` (las reglas R12/R13/R16 siguen igual).
- El formato de frontmatter de concept docs (no se agrega nada al YAML).
- El ciclo SDD (Pol → Sol → Teo ↔ Jhon → Luz → Pau).
- Ningún otro agente, ningún otro script, ninguna otra carpeta del bundle OKF.

## Out of Scope

Explícitamente NO se hace en este MVP:

- **Bidireccional sync automático.** No se genera el sync inverso (spec → concept doc). Solo concept doc → spec. El camino contrario es otra feature.
- **Detección semántica de concept docs afectados.** El script busca paths literales, no intenta comprender prosa. Si Sol escribió "modificamos el ADR de repository pattern" sin path, no detecta.
- **Concept docs en otras carpetas del bundle OKF.** Solo `.opencode/context/concept/*.md`. Las carpetas `decisiones/`, `preferencias/`, `problemas-conocidos/`, `contexto/` quedan fuera del MVP; si la necesidad surge, va en otro change.
- **Validación de que el link sigue vivo.** El link se escribe al archivar; no se re-verifica después. Esa es la función de `scripts/skalling-drift.sh` ya existente (cuando corre sobre el plan archivado, valida que el archivo del link sigue donde dice estar).
- **Auto-generación de concept docs desde specs.** Flujo inverso, ortogonal.
- **Integración con git hooks, CI o ejecución automática al archivar.** Pau lo invoca manualmente como parte de su PASO 5.
- **Reescritura de frontmatter o metadata.** El footer es texto markdown al final del cuerpo, no toca el YAML.
- **Detección de cambios en concept docs por diff.** Solo se detecta por referencia textual en el plan.
- **UI, TUI, API HTTP o servidor.** MVP es CLI Bash solo.

## Success Criteria

Cómo verificamos que el MVP sirve:

- **Pau agrega el footer correcto**: tras ejecutar el script, cada concept doc afectado termina con una sección `## Spec original` cuyo link relativo apunta al path final del plan archivado.
- **Idempotencia**: corriendo el script dos veces sobre el mismo plan, el segundo run no modifica los concept docs (porque ya tienen el footer).
- **Persistencia del primero**: si un concept doc ya tenía `## Spec original` de un plan anterior, no se sobrescribe con el nuevo (se preserva el histórico).
- **Sin falsos positivos**: un plan que no menciona concept docs no produce ningún cambio.
- **Portabilidad**: `bash -n scripts/spec-memory-link.sh` pasa y el script no usa APIs de Bash 4+.
- **Tests verde**: `bash tests/spec-memory-link.test.sh` termina en `0` con implementación correcta.
- **Doctor info**: `bash setup-team-doctor.sh` muestra `ℹ` con la disponibilidad del script y mantiene exit code `0` cuando no hay otros findings.
- **Drift detection verificable**: `bash scripts/skalling-drift.sh .opencode/changes/archive/2026-08/spec-memory-link/` valida los claims de las specs y termina en `0`.
- **Sin regresiones**: el resto de la suite de tests del repositorio sigue pasando.

## Dependencies

- **Bloqueado por**: nada. MVP independiente.
- **Bloquea a**: nada concreto. Cambios futuros pueden extender la detección a otras carpetas del bundle OKF, agregar sync bidireccional, o automatizar la invocación.
- **Dependencias externas**: ninguna. Solo utilidades POSIX ya usadas por el repo (`find`, `grep`, `sed`, `awk`, `dirname`).
- **Compatibilidad mínima**: Bash 3.2 (macOS incluido) y utilidades estándar del entorno Unix del proyecto.

## Affected Areas

Resumen ejecutivo para el design de Sol:

**Scripts**:
- `scripts/spec-memory-link.sh` — nuevo.

**Agentes**:
- `agents-base/Pau.md` — PASO 5 extendido con invocación al script.

**Tests**:
- `tests/spec-memory-link.test.sh` — nuevo.

**Doctor**:
- `setup-team-doctor.sh` — info no bloqueante.
- `command/skalling-doctor.md` — documentación.

**NO se tocan**:
- `constitution/constitucion.md`.
- Frontmatter de concept docs.
- Otros agentes.
- Otros scripts.
- El bundle OKF existente.
