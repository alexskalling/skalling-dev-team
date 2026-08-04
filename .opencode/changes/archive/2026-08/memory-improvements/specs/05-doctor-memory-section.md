# Spec: Sección "Memoria" en `setup-team-doctor.sh`

> **Status**: Draft
> **Mejora**: #5 de memory-improvements
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

---

## Escenario 1: Doctor valida bundle OKF presente

**Given** que `setup-team-doctor.sh` corre con `--project <path>` y existe `.opencode/context/` en el proyecto
**When** el doctor llega a la sección de chequeo per-project
**Then** el doctor MUST invocar la nueva función `check_memory_health()` después de los chequeos de bundle existentes
**Y** `check_memory_health()` MUST imprimir el encabezado de sección `━━━ Memoria (bundle OKF) ━━━` (con el mismo formato visual que las otras secciones)

---

## Escenario 2: Doctor detecta concept docs huérfanos

**Given** que existe `.opencode/context/` con archivos `decisiones/foo.md` y `decisiones/bar.md`
**And** el `decisiones/index.md` referencia solo a `foo.md` (no a `bar.md`)
**When** `check_memory_health()` corre
**Then** el doctor MUST reportar como warning: `⚠️ Concept doc huérfano: decisiones/bar.md (no referenciado desde ningún index.md)`
**Y** debe incluir la ruta completa del archivo huérfano en el warning

---

## Escenario 3: Doctor detecta trabajo-en-curso zombie

**Given** que existe `.opencode/context/trabajo-en-curso/feature-vieja.md` con `timestamp: 2026-05-01T...` en frontmatter (hace más de 30 días desde hoy)
**When** `check_memory_health()` corre
**Then** el doctor MUST reportar como warning: `⚠️ Trabajo-en-curso sin cerrar hace >30 días: trabajo-en-curso/feature-vieja.md (timestamp: 2026-05-01)`
**Y** debe sugerir correr `/skalling-forget` para archivar

---

## Escenario 4: Doctor detecta `index.md` desactualizado

**Given** que existe `.opencode/context/decisiones/index.md` con una lista de 3 docs referenciados
**And** realmente existen 5 archivos `decisiones/*.md` (sin contar el `index.md`)
**When** `check_memory_health()` corre
**Then** el doctor MUST reportar como warning: `⚠️ decisiones/index.md desactualizado: lista 3 docs, encontré 5 archivos .md`
**Y** debe sugerir correr `/skalling-refresh` o regenerar el index

---

## Escenario 5: Doctor detecta duplicados obvios

**Given** que existen dos archivos `.opencode/context/decisiones/x.md` y `.opencode/context/decisiones/y.md` con el mismo `title:` en el frontmatter
**When** `check_memory_health()` corre
**Then** el doctor MUST reportar como **error** (no warning): `✗ Duplicado obvio por title: decisiones/x.md y decisiones/y.md (title: "Migrar a Postgres")`
**Y** en modo `--strict`, este error eleva el exit code a 1

---

## Escenario 6: Doctor valida `log.md` presente

**Given** que existe `.opencode/context/` con varios concept docs
**And** NO existe `.opencode/context/log.md`
**When** `check_memory_health()` corre
**Then** el doctor MUST reportar como info (no warning): `ℹ Sin log.md (se crea en próximo forget o consolidación)`
**Y** NO debe elevar el contador de warnings

---

## Escenario 7: Bundle OKF ausente

**Given** que NO existe `.opencode/context/` en el proyecto
**When** el doctor corre
**Then** la función `check_memory_health()` NO debe ejecutarse (no hay nada que chequear)
**Y** el doctor existente ya maneja este caso con el mensaje `info "Sin bundle OKF todavía. Corré /skalling-init."`

---

## Escenario 8: `command/skalling-doctor.md` refleja la nueva sección

**Given** que la nueva sección existe en `setup-team-doctor.sh`
**When** un usuario lee `command/skalling-doctor.md`
**Then** la tabla de output MUST incluir una nueva fila "Memoria (bundle OKF)" con el mismo formato que las demás filas
**Y** el comando MUST documentar los nuevos findings posibles: huérfanos, WIP zombie, index desactualizado, duplicados

---

## Reglas MUST (obligatorias)

1. `setup-team-doctor.sh` MUST definir la función `check_memory_health()` e invocarla desde `check_project_install()` solo cuando exista `.opencode/context/`.
2. La función MUST emitir los 5 chequeos: huérfanos, WIP zombie (>30 días), index desactualizado, duplicados obvios, log.md presente.
3. La severidad MUST ser: duplicados → **error**; huérfanos/WIP zombie/index desactualizado → **warning**; log.md ausente → **info**.
4. El formato de output MUST ser consistente con las demás secciones (mismos iconos, colores, contadores OK/Warn/Err).
5. `command/skalling-doctor.md` MUST actualizarse para listar la nueva sección "Memoria (bundle OKF)" en su tabla de output.
6. La función NO debe tocar archivos del bundle OKF — solo lectura.
7. La función NO debe depender de herramientas externas más allá de `bash`, `grep`, `find`, y opcionalmente `yq` para parsear YAML (degradar gracefully si `yq` no está — caer a regex simple sobre el frontmatter).

## Reglas SHOULD (recomendadas)

1. El chequeo de huérfanos SHOULD ser eficiente: `grep -l <nombre> **/index.md` en lugar de leer cada index completo.
2. El chequeo de WIP zombie SHOULD usar el `timestamp` del frontmatter como fecha de referencia; si falta el frontmatter, SHOULD usar el `mtime` del archivo como fallback.
3. El chequeo de duplicados SHOULD normalizar el `title:` (lowercase, trim, sin acentos) antes de comparar — para detectar "Postgres" vs "postgres".
4. El threshold de 30 días SHOULD ser configurable por variable de entorno (`SKALLING_WIP_ZOMBIE_DAYS`, default 30).
5. El output SHOULD incluir el conteo total de concept docs chequeados al inicio de la sección.

## Reglas MAY (opcionales)

1. La función MAY sugerir correr `/skalling-forget` o `/skalling-refresh` cuando detecta issues.
2. La función MAY colorear diferente los warnings de memoria vs los warnings de instalación (para distinguir visualmente).
3. La función MAY agrupar issues por área (decisiones/, preferencias/, trabajo-en-curso/) en el output.

---

## Criterios de Aceptación (resumen)

- [ ] Función `check_memory_health()` existe en `setup-team-doctor.sh` y se invoca solo cuando `.opencode/context/` existe.
- [ ] Los 5 chequeos funcionan: huérfanos, WIP zombie, index desactualizado, duplicados, log.md.
- [ ] Severidades respetadas: duplicados = error, resto = warning o info según corresponda.
- [ ] Test bash en `tests/doctor-memory.test.sh` cubre los 5 chequeos con fixtures sintéticas.
- [ ] `command/skalling-doctor.md` actualizado con la fila "Memoria (bundle OKF)" en su tabla de output.
- [ ] `bash setup-team-doctor.sh --strict` retorna exit 1 cuando hay un duplicado obvio.
- [ ] El doctor corre sin `yq` instalado (degradación graceful).

---

## Out of Spec (explícitamente NO incluido)

- Auto-fix de issues detectados (el doctor solo reporta; `/skalling-refresh` o `/skalling-forget` son los que arreglan).
- Validación semántica del contenido de los concept docs (el doctor chequea estructura, no semántica — eso es trabajo de Pol en mejora #3).
- Chequeo de contradicciones entre concept docs (vive en la mejora #3 de Pol, no en el doctor).
- Notificación externa (email, Slack) cuando se detectan issues — el doctor solo imprime a stdout/stderr.
- Modificación del comportamiento del doctor en `--global-only` (la sección de memoria es per-project only).
- Chequeo de `.opencode/changes/` o `docs/` (eso es scope de otros cambios, no del doctor de bundle).
- Reescritura completa del doctor en otro lenguaje (sigue bash; R7 Clean Architecture no aplica a scripts de tooling).
