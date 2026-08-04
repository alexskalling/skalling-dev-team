# Design: Memory Improvements — 5 mejoras al sistema de memoria de Skalling

> **Status**: Draft (pendiente aprobación)
> **Author**: Sol
> **Inputs**: `proposal.md` + `specs/01-concept-template.md` ... `specs/05-doctor-memory-section.md`
> **Date**: 2026-08-03

---

## 1. Contexto y Alcance

Esta tanda introduce cinco mejoras al sistema de memoria de Skalling (bundle OKF en `.opencode/context/`), todas dentro del framework. **Cero binarios externos, cero cambios constitucionales, cero migraciones de datos existentes.**

### Restricciones duras (heredadas de Pol)

- NO se toca `constitution/constitucion.md`.
- NO se tocan otros templates OKF (solo `concept.template.md`).
- NO se toca `docs/`.
- NO se migran concept docs existentes (backward compat).
- Todo es reversible vía `git revert`.

---

## 2. Arquitectura común

Antes de bajar a cada mejora, hay dos decisiones arquitectónicas que aplican aMejoras 4 y 5 (y opcionalmente a 3).

### 2.1 Helper bash compartido: `scripts/lib/lib-memory-check.sh`

Mejora 4 (`mem-review.sh`) y Mejora 5 (`check_memory_health()` del doctor) necesitan **la misma lógica de detección**: huérfanos, WIP zombie, duplicados por title, vigencia > N meses. Si la copiamos, cada vez que cambien los umbrales hay que tocar dos lugares y se desincronizan.

**Decisión**: extraer un helper bash compartido, sourceable desde ambos scripts.

**Funciones exportadas** (API del helper):

```bash
skalling_parse_yaml_field(file, field)   # extrae un campo del frontmatter YAML con regex (sin yq)
skalling_find_orphans(context_dir)        # echo: lista de paths no referenciados desde ningún index.md
skalling_find_zombie_wip(context_dir, days)  # echo: paths en trabajo-en-curso/ con timestamp > N días y todas las tareas [x]
skalling_find_duplicates(context_dir)    # echo: pares de paths con title normalizado idéntico
skalling_find_stale(context_dir, months)  # echo: paths de concept docs sin referenciar por > N meses
skalling_find_superseded(context_dir)     # echo: paths con frontmatter supersedes: (lógica legacy)
```

**Parser YAML sin dependencias**: regex sobre el bloque `---\n...\n---` al inicio del archivo. Ej: `^title:\s*(.+)$` con `grep -E`. Si está disponible `yq`, se usa como accelerator (cached lookup). Si no, fallback a regex. Esto evita el acoplamiento a `yq` (no está en todas las distros).

**Ubicación**: `scripts/lib/lib-memory-check.sh` (al lado de `lib-os.sh` y `lib-stack-detect.sh`).

**Distribución**: `install-global.sh` ya copia `scripts/lib/` recursivamente (vía `install_data_files` + future copy). Pero hoy `install_global.sh` solo copia `scripts/merge-helper.sh` individualmente. **Acción concreta**: agregar install step en `install-global.sh` que copie `scripts/lib/lib-memory-check.sh` a `$OPENCODE_DIR/scripts/lib/`. Esto es un cambio de 5 líneas en `install-global.sh` (nueva tarea 4.1.b).

### 2.2 Patrón de inyección del memory protocol (Mejora 2)

Los prompts de los agentes en `agents-base/*.md` son texto estático que opencode carga en el contexto. El modelo **no carga otros archivos en runtime**. Por eso, "inyectar el snippet" tiene dos lecturas posibles:

- **(A) Single source + copia con pointer**: el snippet canónico vive en `templates/agents/snippets/memory-protocol.md`. Cada agente tiene una sección `## 🧠 Memory Protocol` que **copia el contenido del snippet** dentro del prompt, con un comment block al inicio del bloque: `<!-- Sincronizado con templates/agents/snippets/memory-protocol.md. Si editás esto, sincronizá ambos lados. -->`. El snippet sigue siendo la "fuente de verdad" desde el punto de vista de **diseño** (uno solo se mantiene), aunque en runtime el modelo vea la copia.
- **(B) Solo referencia**: en cada agente va una sección `## 🧠 Memory Protocol` con un texto mínimo ("Leé y aplicá `templates/agents/snippets/memory-protocol.md` antes de cerrar tu handoff"). El resto del contenido NO se copia. Riesgo: si el modelo no carga el archivo en runtime, la instrucción es no-op.
- **(C) Solo inline, sin pointer**: el contenido se copia en cada agente sin link al snippet canónico. Más simple pero pierde la propiedad de "single source of truth" para mantenimiento.

**Recomendación**: opción (A). El comment block al inicio del snippet copiado es la disciplina que permite que un humano (no el modelo) sincronice cambios. El trade-off DRY-vs-mantenimiento se resuelve a favor del mantenimiento del snippet como contrato único.

**Decisión a confirmar con el usuario** (ver sección 9).

### 2.3 Formato de la sección de conflictos en `proposal.md` (Mejora 3)

La sección se inserta **siempre al final del `proposal.md`**, después de `## Success Criteria` y antes de `## Stakeholders`. Esto es una posición fija en el documento, no negociable. El formato exacto:

```markdown
## ⚠️ Conflictos detectados
- **Concept doc contradicho**: [path]
- **Razón de contradicción**: [explicación]
- **Propuesta de resolución**: [A: supersedes / B: cambiar feature / C: explayar ambas]

## ✅ Sin conflictos con memoria existente
- Revisado: YYYY-MM-DD
- Áreas consultadas: decisiones/, preferencias/, problemas-conocidos/
- Concept docs relevantes leídos: [lista con paths]
```

**Mutuamente excluyentes**: solo una de las dos secciones aparece. NUNCA las dos. NUNCA ninguna (proposal sin sección es inválido).

---

## 3. Diseño por mejora

### 3.1 Mejora 1 — Template What / Why / Where / Learned

**Archivos a tocar**:
- `templates/okf/concept.template.md` (reescritura del body)
- `agents-base/Pau.md` (instrucción explícita de rechazar docs nuevos sin las 4 secciones)
- `tests/concept-template.test.sh` (nuevo)

**Decisiones técnicas**:

1. **Body del template** (reemplaza secciones líneas 12-34):
   ```markdown
   # [Nombre del Concepto]

   ## What
   [Una o dos oraciones. Qué es, qué rol cumple.]

   ## Why
   [Qué dolor motivó la existencia de este concepto. No la feature, el dolor.]

   ## Where
   - `path/to/file.ts` — [qué hace]
   - `path/to/related.ts` — [cómo se relaciona]

   ## Learned
   [Workaround, decisión forzada, gotcha descubierto durante implementación.
   Si no hay nada útil, usar: _(sin contenido por ahora — completar cuando aplique)_]
   ```

2. **Frontmatter**: SIN CAMBIOS. Sigue siendo el schema OKF v0.2 (`type`, `title`, `description`, `resource`, `tags`, `timestamp`, `agent`, `confidence`, `supersedes`).

3. **Orden de secciones**: fijo (What → Why → Where → Learned). Pau no puede reordenar.

4. **Sección vacía = placeholder aceptado**: si Pau legítimamente no tiene contenido para una sección, debe usar el literal `_(sin contenido por ahora — completar cuando aplique)_` en esa sección. El doc sigue siendo válido.

5. **Backward compat**: docs existentes con las 5 secciones legacy (Qué es / Cómo se usa / Donde vive / Versiones / Links) siguen siendo válidos. NO se migran. Razonamiento: la memoria histórica es valiosa; forzar migración es una dictadura de formato que agrega ruido sin valor.

6. **Validación**: la hace Pau manualmente al revisar el doc antes de archivar. NO es un script en esta tanda (el chequeo de bundle vive en Mejora 5). El script `tests/concept-template.test.sh` solo valida la estructura del template mismo (los 4 headers presentes, en el orden correcto).

**Riesgos y mitigaciones**:

| Riesgo | Mitigación |
|---|---|
| Pau no adopta el template por inertia | Pau.md instrucción explícita + check de aceptación es checkbox en su flujo ("¿Las 4 secciones What/Why/Where/Learned están presentes?") |
| Otros agentes (Sol, Teo) generan docs sin las 4 secciones | Solo Pau consolida docs definitivos. Sol/Teo solo dejan rastro en `trabajo-en-curso/` (no definitive docs). |
| Template reescrito rompe searches que matchean "Qué es" | Backward compat: docs existentes con "Qué es" siguen siendo válidos. Solo aplica a docs nuevos. |

### 3.2 Mejora 2 — Memory Protocol Snippet

**Archivos a tocar**:
- `templates/agents/snippets/memory-protocol.md` (nuevo, single source of truth)
- `agents-base/Alex.md`, `Jhon.md`, `Jes.md`, `Luz.md`, `Sol.md`, `Teo.md` (sección `## 🧠 Memory Protocol`)
- `agents-base/Pau.md` (sección + instrucciones de consolidación)
- `agents-base/Pol.md` (sección adicional; la fase de "chequeo de conflictos" vive en Mejora 3)
- `tests/memory-protocol.test.sh` (nuevo)

**Snippet canónico** (contenido de `templates/agents/snippets/memory-protocol.md`):

```markdown
# 🧠 Memory Protocol

## Cuándo evaluar guardar

Antes de cerrar tu handoff al siguiente agente (o tu propio ciclo si sos terminal), **evaluá** si lo que aprendiste/decidiste merece guardarse.

## Dónde guardar

- **Memoria operativa** (transitoria, entre ciclos): `.opencode/context/trabajo-en-curso/`
  - Template: `templates/okf/work-in-progress.template.md`
  - Ejemplos: decisiones pendientes, bloqueos, próximos pasos, gotchas no obvios
- **Memoria definitiva** (consolidada por Pau): `.opencode/context/decisiones/`, `preferencias/`, `problemas-conocidos/`, etc.
  - Los agentes NO escriben memoria definitiva. Solo Pau la consolida.

## Cuándo guardar

Guardá en `trabajo-en-curso/` si la información:
- Te sirve a vos mismo si volveles al proyecto en 3 semanas
- Influye en otra decisión futura
- Es un workaround o gotcha no obvio
- Cambia de estado un feature (de "en curso" a "bloqueado")

**NO guardes** trivialidades: typos, renames, configs de una línea, sin impacto futuro.

## Cómo marcar contradicciones

Si detectás que lo que hiciste/decidiste contradice un concept doc existente:

1. En tu handoff al siguiente agente, agregá:
   ```json
   "contradicciones_detectadas": ["path/al/concept/doc — razón breve"]
   ```
2. NO proceder como si nada. Notificar a Alex para escalar al usuario.

## Qué NO guardar (R10)

- Secrets, credenciales, API keys, tokens
- Información personal identificable
- Contenido que no ayude a entender el proyecto en el futuro

## Recordatorio R12

El bundle OKF es **local al proyecto**. No se replica ni sincroniza con la nube. El backup es responsabilidad del usuario (git).
```

**Cómo se inyecta en los 8 agentes**:

Cada uno de los 8 archivos `agents-base/*.md` recibe una sección `## 🧠 Memory Protocol` agregada cerca del final (después de la sección principal del agente, antes de "🗣️ MI PERSONALIDAD" o "📋 INSTRUCCIONES PARA EL USUARIO"). El contenido de la sección es **el snippet canónico** completo, con un header comment que indica la sincronización:

```markdown
<!-- ═══════════════════════════════════════════════════════════════════
     SINCRONIZADO CON: templates/agents/snippets/memory-protocol.md
     Si editás este bloque, sincronizá ambos lados.
     ═══════════════════════════════════════════════════════════════════ -->

## 🧠 Memory Protocol

[Contenido del snippet literal]

<!-- FIN SINCRONIZADO -->
```

**Pau.md recibe una versión extendida** que agrega la fase de "consolidación":

```markdown
## 🧠 Memory Protocol (extendido — Pau)

[Contenido del snippet + sección adicional:]

### Mi rol adicional: consolidación

Cuando Luz emite Quality Gate PASSED, yo:
1. Reviso `.opencode/context/trabajo-en-curso/` y consolido entries significativos en `decisiones/`, `preferencias/`, `problemas-conocidos/`, etc.
2. Uso el template `concept.template.md` (What/Why/Where/Learned) solo para docs nuevos.
3. Muevo entries completos (todas las tareas `[x]`) a `.opencode/context/archive/<YYYY-MM>/`.
4. Actualizo `index.md` cuando consolido o archivo.
5. Frontmatter `supersedes:` en el doc nuevo si reemplaza uno anterior.
```

**Test bash** (`tests/memory-protocol.test.sh`): valida que los 8 agentes tienen la sección `## 🧠 Memory Protocol` y que el contenido coincide (o al menos cubre los 3 puntos clave: cuándo guardar, dónde, cómo marcar contradicciones).

**Riesgos y mitigaciones**:

| Riesgo | Mitigación |
|---|---|
| 8 copias se desincronizan del snippet canónico | Comment block en cada copia como "single source" reminder. El test `memory-protocol.test.sh` valida la presencia de los 3 puntos clave. |
| Modelo "ignora" el snippet porque el prompt es largo | Sección cerca del final del prompt (no al medio). El modelo opencode lee todo. Si la sección se vuelve demasiado larga, considerar extraerla a un skill (out of scope de esta tanda). |
| Pau consolida sin adhesión de Teo al memory protocol | El snippet instruye a todos los agentes. Pau solo recibe el extendido. Alex puede recordar el chec en cada handoff. |

### 3.3 Mejora 3 — Detección de conflictos en Pol

**Archivos a tocar**:
- `agents-base/Pol.md` (nueva fase "Chequeo de conflictos" antes de cerrar el proposal)
- `tests/conflict-detection.test.sh` (nuevo)

**Diseño de la fase en Pol.md** (se agrega entre FASE 4 — Pase a Sol y la firma de cierre):

```markdown
### FASE 5 — Chequeo de conflictos contra memoria existente (OBLIGATORIO)

Antes de cerrar el `proposal.md`, **siempre** chequeo si la propuesta contradice memoria existente:

1. **Leo el bundle OKF** si existe:
   - `.opencode/context/decisiones/` (ADRs activos)
   - `.opencode/context/preferencias/` (convenciones del equipo)
   - `.opencode/context/problemas-conocidos/` (workarounds activos)
   - `.opencode/context/trabajo-en-curso/` (features activas — SHOULD)

2. **Filtro por relevancia**: priorizo `confidence >= 0.8` y `type: Decision` o `type: Preference`. Tipo `Context` se ignora.

3. **Si encuentro contradicción**, agrego al final del `proposal.md` (después de `## Success Criteria`, antes de `## Stakeholders`):
   ```markdown
   ## ⚠️ Conflictos detectados
   - **Concept doc contradicho**: [path]
   - **Razón de contradicción**: [qué dice el concept doc vs qué propone la feature]
   - **Propuesta de resolución**: [A: supersedes / B: cambiar feature / C: explayar ambas]
   ```
   Y escalo a Alex para presentar al usuario con opciones.

4. **Si NO hay contradicción**, agrego:
   ```markdown
   ## ✅ Sin conflictos con memoria existente
   - Revisado: YYYY-MM-DD
   - Áreas consultadas: decisiones/, preferencias/, problemas-conocidos/
   - Concept docs relevantes leídos: [lista]
   ```

5. **Si el bundle está vacío o corrupto**, NO declaro "sin conflictos". Escalo a Alex con el mensaje: `⚠️ Bundle OKF no legible. No puedo chequear conflictos. Recomiendo correr /skalling-refresh antes de aprobar esta propuesta.`

**Regla absoluta**: un `proposal.md` SIN sección de conflictos es **inválido**. No se aprueba sin ella.

**Para fast-track e inline**: el chequeo formal NO se aplica (no hay proposal). Alex hace un chequeo visual rápido y pregunta al usuario si detecta una contradicción obvia.

**MAY delegar**: si el bundle es muy grande (>50 concept docs relevante), puedo delegar el resumen a Jes. Pero YO mantengo la responsabilidad del veredicto.
```

**Test bash** (`tests/conflict-detection.test.sh`): sintético. Crea un bundle con 1 concept doc de tipo "Preference" que dice "estilo: TypeScript strict" y simula que Pol escribe un proposal que dice "vamos a usar dynamic typing". El test verifica que la sección `## ⚠️ Conflictos detectados` aparece con el path correcto.

**Riesgos y mitigaciones**:

| Riesgo | Mitigación |
|---|---|
| Pol declara "sin conflictos" sin haber leído | Frase explícita en Pol.md: "Si el bundle está vacío o corrupto, NO declaro 'sin conflictos'". Regla MUST. |
| Bundle enorme hace el chequeo lento | Filtrado por `confidence >= 0.8` y `type: Decision|Preference`. Skip tipo `Context`. Delega a Jes si > 50 docs. |
| Falso positivo (concept doc no aplica realmente) | El usuario (vía Alex) decide. Pol solo PROPONE la contradicción. |
| Falso negativo (Pol no detecta) | Cochrane: Pau archiva y al consolidar puede descubrir contradicciones. El doctor también levantará warnings (Mejora 5). |

### 3.4 Mejora 4 — `/skalling-forget` con consolidación (`mem-review`)

**Archivos a tocar**:
- `scripts/lib/lib-memory-check.sh` (nuevo, helper compartido con Mejora 5)
- `scripts/mem-review.sh` (nuevo)
- `command/skalling-forget.md` (reescrito)
- `tests/mem-review.test.sh` (nuevo)
- `tests/skalling-forget.test.sh` (nuevo, integración)

**Diseño del script `scripts/mem-review.sh`**:

```
Entrada: --target <project_dir> [--dry-run]
Salida: JSON-like o tabla formateada con candidatos agrupados en 4 categorías

Categorías (orden fijo):
1. Duplicados        (por title normalizado en la misma carpeta)
2. WIP Zombie        (timestamp > 30 días Y todas las tareas [x])
3. Vigencia          (no referenciado desde index.md ni cross-refs > 6 meses)
4. Superseded        (frontmatter supersedes: presente)

Cada candidato incluye:
- path absoluto
- timestamp
- razón
- opciones sugeridas (A/B/C/D)

Umbrales (env vars):
- SKALLING_WIP_ZOMBIE_DAYS   (default 30)
- SKALLING_STALE_MONTHS      (default 6)
```

**Diseño del comando reescrito** (`command/skalling-forget.md`):

```
PASO 1: Corro mem-review.sh (puede ser --dry-run)
PASO 2: Agrupo output en 4 categorías
PASO 3: Por cada candidato individualmente, pregunto:
   A) Archivar (.opencode/context/archive/<YYYY-MM>/)
   B) Borrar definitivamente
   C) Conservar
   D) Ver antes de decidir
PASO 4: Aplico decisiones (preferir archivar sobre borrar)
PASO 5: Loggeo en .opencode/context/log.md con formato detallado
PASO 6: Corro setup-team-doctor.sh --strict para validar
```

**Tests**:

- `tests/mem-review.test.sh`:
  - Fixture: bundle con 2 docs duplicados, 1 WIP zombie, 1 stale, 1 superseded
  - Assertions: mem-review detecta los 4, agrupa en el orden correcto
- `tests/skalling-forget.test.sh`:
  - Fixture: bundle sintético
  - End-to-end: invocar el comando (con respuestas A/B/C/D pre-cargadas), validar que archiva correctamente, que `log.md` se actualiza con el formato esperado

**Riesgos y mitigaciones**:

| Riesgo | Mitigación |
|---|---|
| Parsing YAML frágil | Regex simple + fallback a `mtime` si falta frontmatter. `yq` como accelerator (no required). |
| Falsos positivos en duplicados (títulos similares pero conceptos distintos) | Normalización: lowercase + trim + sin acentos. Decisión final siempre del usuario. |
| Archivar un doc referenciado desde otro produce huérfano | Doctor corre post-purga y avisa (escenario 8 del spec). |
| Bundle grande hace el script lento | Filtrado por subcarpeta, no recursión profunda innecesaria. |

### 3.5 Mejora 5 — Doctor memoria

**Archivos a tocar**:
- `setup-team-doctor.sh` (nueva función `check_memory_health()`)
- `command/skalling-doctor.md` (actualizar tabla de output)
- `tests/doctor-memory.test.sh` (nuevo)

**Diseño de `check_memory_health()`**:

```bash
check_memory_health() {
    section "Memoria (bundle OKF)"

    # Guard: si no hay bundle, skip
    if [[ ! -d "$PROJECT_DIR/.opencode/context" ]]; then
        info "Sin bundle OKF todavía. Corré /skalling-init."
        return 0
    fi

    # Sourcear el helper
    source "$(dirname "$0")/scripts/lib/lib-memory-check.sh"

    # 1. Huérfanos
    local orphans; orphans="$(skalling_find_orphans "$PROJECT_DIR/.opencode/context")"
    if [[ -n "$orphans" ]]; then
        while IFS= read -r f; do
            warn "Concept doc huérfano: $f (no referenciado desde ningún index.md)"
        done <<< "$orphans"
    else
        ok "Sin concept docs huérfanos"
    fi

    # 2. WIP zombie (>30 días)
    local zombie_days="${SKALLING_WIP_ZOMBIE_DAYS:-30}"
    local zombies; zombies="$(skalling_find_zombie_wip "$PROJECT_DIR/.opencode/context" "$zombie_days")"
    if [[ -n "$zombies" ]]; then
        while IFS= read -r f; do
            warn "Trabajo-en-curso sin cerrar hace >${zombie_days}d: $f — corré /skalling-forget"
        done <<< "$zombies"
    else
        ok "Sin trabajo-en-curso zombie"
    fi

    # 3. Index desactualizado
    for subdir in decisiones preferencias problemas-conocidos; do
        local idx="$PROJECT_DIR/.opencode/context/$subdir/index.md"
        if [[ -f "$idx" ]]; then
            local listed; listed="$(grep -c '\.md' "$idx" || echo 0)"
            local actual; actual="$(find "$PROJECT_DIR/.opencode/context/$subdir" -maxdepth 1 -name "*.md" -not -name "index.md" -not -name "log.md" -not -name "README.md" | wc -l)"
            if [[ "$listed" -ne "$actual" ]]; then
                warn "$subdir/index.md desactualizado: lista $listed, encontré $actual .md"
            else
                ok "$subdir/index.md coherente"
            fi
        fi
    done

    # 4. Duplicados (ERROR)
    local dups; dups="$(skalling_find_duplicates "$PROJECT_DIR/.opencode/context")"
    if [[ -n "$dups" ]]; then
        err "Duplicado obvio por title: $dups"
    else
        ok "Sin duplicados obvios"
    fi

    # 5. log.md
    if [[ -f "$PROJECT_DIR/.opencode/context/log.md" ]]; then
        ok "log.md presente"
    else
        info "Sin log.md (se crea en próximo forget o consolidación)"
    fi
}
```

**Invocación**: al final de `check_project_install()`, después del check de design-system.md (R13):

```bash
# Nueva sección
check_memory_health
```

**Actualizar `command/skalling-doctor.md`**: agregar fila "Memoria (bundle OKF)" a la tabla de output, con findings posibles (huérfanos, WIP zombie, index desactualizado, duplicados).

**Test bash** (`tests/doctor-memory.test.sh`):

```
Fixture: mktemp -d con .opencode/context/decisiones/x.md (no en index),
        .opencode/context/trabajo-en-curso/y.md (timestamp viejo, todas [x]),
        .opencode/context/decisiones/index.md (lista 1, hay 2 archivos),
        decisiones/a.md y decisiones/b.md con mismo title.

Assertions:
- Doctor detecta los 4 issues
- Severidades respetadas (duplicado = error, resto = warning)
- --strict exit 1 por el error
```

**Riesgos y mitigaciones**:

| Riesgo | Mitigación |
|---|---|
| Doctor tarda mucho en bundle grande | Helper usa regex simple, no recursión profunda. Si es lento, optimizar en otra iteración. |
| Falsa detección de "sin referenciar" (doc referenciado en body, no en index) | Spec 5 escenario 2 dice "no referenciado desde ningún index.md". Cross-refs en body no cuentan. Scope claro. |
| `yq` no instalado → falla el doctor | Helper degrada gracefully a regex. Doctor no depende de `yq`. |

---

## 4. Orden de implementación y dependencias

```
Fase 1 (Concept Template)
   ↓
Fase 2 (Memory Protocol) ───────┐
   ↓                            │
Fase 3 (Conflict Detection) ────┤
                                │
Fase 4 (lib-memory-check.sh) ◄──┤ (helper compartido)
   ↓                            │
Fase 5 (mem-review + forget) ◄──┤
   ↓                            │
Fase 6 (Doctor memoria) ◄───────┘
   ↓
Fase 7 (Cierre: CHANGELOG, README, archive)
```

**Justificación del orden**:

- **Fase 1 primero**: template es independiente. No bloquea a nadie, pero concept docs escritos por Pau desde el día 1 del feature deben seguirlo. Mejor tenerlo listo antes.
- **Fase 2 antes que 3**: el memory protocol es inyectado en los 8 agentes. Pol lo necesita cargado para poder ejecutar la fase de "chequeo de conflictos" (Mejora 3). Pero la fase 3 puede arrancar ANTES de terminar la 2 si solo se enfoca en Pol.md.
- **Fase 4 (helper) antes que 5 y 6**: mem-review y doctor comparten la lógica de detección. Si escribimos mem-review primero y luego el doctor, duplicamos código. El helper es la abstracción correcta.
- **Fase 5 antes que 6**: el doctor puede correr sobre el helper; pero el mem-review es la herramienta que produce los datos que el doctor detecta. Haddock: "primero la herramienta, después el auditor".
- **Fase 7 al final**: CHANGELOG, README, archive. Después de la regresión completa.

**Tests independientes**: cada fase tiene su test bash. La regresión final corre todos.

---

## 5. Estrategia de adopción

### 5.1 ¿Activación gradual o todo de una?

**Recomendación: todo de una, pero dividido en commits discretos.**

Razonamiento:
- Las 5 mejoras son independientes funcionalmente, pero Conceptualmente forman un sistema ("memoria escribible + trazable + saneable").
- Cada fase tiene su test. Si el equipo decide revertir una fase, el `git revert` es por commit.
- Hacerlo gradual (tipo "shipeamos solo Mejora 1 esta semana") genera métricas parciales confusas. Pau podría empezar a usar el nuevo template pero el memory protocol no estar cargando en Alex, generando asimetrías.

**Pero**: el orden de merges puede ser:
1. PR #1: Fase 1 (template) + Fase 2 (memory protocol) + sus tests → bajo riesgo, sin tocar scripts.
2. PR #2: Fase 4 (helper) + Fase 5 (mem-review + forget) + Fase 6 (doctor) + sus tests → cambia scripts, riesgo medio.
3. PR #3: Fase 3 (conflict detection) + Fase 7 (CHANGELOG, README) → cambio de comportamiento en Pol, riesgo bajo.

### 5.2 Backward compat

- Concept docs legacy (con "Qué es" / "Cómo se usa") siguen siendo válidos.
- El comando `/skalling-forget` reescrito conserva la lógica de superseded (no se rompe nada).
- El doctor agrega una sección, no modifica las existentes.
- El memory protocol es aditivo: si un agente no lo aplica, su comportamiento previo sigue funcionando.

### 5.3 Monitoreo post-deploy

- El success criteria del proposal es verificable manualmente.
- Se sugiere agregar un test sintético en `tests/concept-template.test.sh` que verifique que un doc de prueba SIN las 4 secciones es identificable como incompleto (para que Pau tenga evidencia ejecutable).

---

## 6. Archivos a tocar (resumen)

| Categoría | Archivo | Acción |
|---|---|---|
| Template | `templates/okf/concept.template.md` | Rewriter body |
| Template | `templates/agents/snippets/memory-protocol.md` | Nuevo |
| Agent | `agents-base/Alex.md` | Agregar sección |
| Agent | `agents-base/Pol.md` | Sección + Fase 5 (conflict detection) |
| Agent | `agents-base/Jes.md` | Sección |
| Agent | `agents-base/Sol.md` | Sección |
| Agent | `agents-base/Teo.md` | Sección |
| Agent | `agents-base/Jhon.md` | Sección |
| Agent | `agents-base/Luz.md` | Sección |
| Agent | `agents-base/Pau.md` | Sección extendida + instrucción de rechazo |
| Command | `command/skalling-forget.md` | Rewriter |
| Command | `command/skalling-doctor.md` | Update tabla |
| Script | `scripts/lib/lib-memory-check.sh` | Nuevo |
| Script | `scripts/mem-review.sh` | Nuevo |
| Script | `setup-team-doctor.sh` | Nueva función + invocación |
| Script | `install-global.sh` | Copiar nuevo helper (.lib) |
| Test | `tests/concept-template.test.sh` | Nuevo |
| Test | `tests/memory-protocol.test.sh` | Nuevo |
| Test | `tests/conflict-detection.test.sh` | Nuevo |
| Test | `tests/lib-memory-check.test.sh` | Nuevo |
| Test | `tests/mem-review.test.sh` | Nuevo |
| Test | `tests/skalling-forget.test.sh` | Nuevo |
| Test | `tests/doctor-memory.test.sh` | Nuevo |
| Docs | `CHANGELOG.md` | Entrada en [Unreleased] |
| Docs | `README.md` | Párrafo en sección memoria |

**Archivos NO tocados** (verificado):
- `constitution/constitucion.md` ❌
- `docs/**` ❌
- Otros templates OKF (decision, preference, workaround, etc.) ❌
- `.opencode/context/` del repo (memoria de runtime) ❌

---

## 7. Test Strategy (R4)

**Patrón**: bash scripts con `assert_file_exists`, `assert_file_contains`, `assert_dir_exists`, helpers `pass/fail/log`. Fixtures con `mktemp -d`. Cada test es un `.sh` ejecutable, conteo PASS/FAIL, exit 1 si FAIL > 0.

**Cobertura de tests por fase**:

| Fase | Test | Qué valida |
|---|---|---|
| 1 | `tests/concept-template.test.sh` | Los 4 headers `## What`, `## Why`, `## Where`, `## Learned` están en el template, en orden, en el body |
| 2 | `tests/memory-protocol.test.sh` | Los 8 agentes tienen la sección `## 🧠 Memory Protocol` con los 3 puntos clave (cuándo guardar, dónde, cómo marcar contradicciones) |
| 3 | `tests/conflict-detection.test.sh` | Pol.md contiene la fase de "chequeo de conflictos" con los 3 escenarios (sin conflictos / con conflictos / bundle corrupto) |
| 4 | `tests/lib-memory-check.test.sh` | Cada función del helper retorna los resultados esperados sobre fixtures sintéticas |
| 5 | `tests/mem-review.test.sh` | mem-review detecta las 4 categorías con fixtures sintéticas |
| 5 | `tests/skalling-forget.test.sh` | End-to-end: comando archiva, log.md actualizado, doctor post-purga detecta issues |
| 6 | `tests/doctor-memory.test.sh` | Los 5 chequeos detectan sus issues con fixtures, severidades respetadas, --strict retorno 1 en error |

**Regresión**: `tests/setup.test.sh` sigue corriendo. Se le agrega un check que los 6 nuevos archivos de test existen y son ejecutables.

---

## 8. Riesgos globales y mitigaciones

| Riesgo | Probabilidad | Mitigación |
|---|---|---|
| Pau adopta parcialmente el template (algunos docs sí, otros no) | Media | El test + la instrucción en Pau.md son la primera línea. La auditoría de Luz al cerrar el plan verifica. |
| Mem-review rompe bundle (archiva lo que no debe) | Baja | Doctor post-purga detecta issues. El usuario puede revertir moviendo el archivo de vuelta. |
| Doctor se vuelve lento en bundle grande | Baja | Optimización es out of scope. Helper usa regex, no parseo profundo. |
| Helper bash tiene bugs y se rompe todo | Baja | Tests unitarios del helper (Fase 4). Doctor y mem-review corren independientemente. |
| Snippet se desincroniza entre los 8 agentes | Media | Comment block al inicio del snippet copiado. Test verifica presencia de los 3 puntos clave. |
| Conflict detection flaggea falsos positivos | Alta | La detección es heurística (palabras clave, confianza alta). El usuario descarta vía Alex. |
| Concept docs legacy quedan "huérfanos" por el chequeo de index | Media | El test valida solo sobre docs nuevos. Docs legacy no aparecen como huérfanos automáticamente. |

---

## 9. Decisiones que necesitan confirmación del usuario

### 9.1 Forma de inyección del memory protocol (Mejora 2)

**Default propuesto**: opción (A) — single source en `templates/agents/snippets/memory-protocol.md` + contenido copiado en cada agente con comment block de pointer.

**Alternativas**:
- (B) Solo referencia al path en cada agente (más DRY, pero el modelo no carga archivos en runtime → instrucción ignorada).
- (C) Solo inline, sin pointer al snippet (más simple, pero pierde "single source of truth").

**Recomendación fuerte**: opción (A). El comment block al inicio es la disciplina de mantenimiento. El snippet canónico es el "contrato", y las 8 copias son "instantáneas" que el agente ve en su prompt.

### 9.2 Umbrales por defecto

| Umbral | Default propuesto | Env var |
|---|---|---|
| WIP zombie (días) | 30 | `SKALLING_WIP_ZOMBIE_DAYS` |
| Vigencia (meses) | 6 | `SKALLING_STALE_MONTHS` |

**Default 30 días / 6 meses coincide con la constitución de Pau** ("cada 6 meses, Pau revisa entries sin referenciar"). Si el usuario quiere otro número, marque en la confirmación.

### 9.3 Out of scope (recordatorio)

- No se introduce engram binario.
- No se implementa FTS5 ni búsqueda full-text.
- No se migran concept docs existentes.
- No se cambia la constitución.
- No se hace captura pasiva (hooks).

Estas exclusiones están en el proposal. Si querés agregar algo, decime antes de aprobar el plan.

---

## 10. Referencias cruzadas

- `proposal.md` — Success criteria, Rollback plan, Stakeholders
- `specs/01-concept-template.md` — Escenarios 1-5, reglas MUST/SHOULD/MAY
- `specs/02-memory-protocol-snippet.md` — Escenarios 1-5
- `specs/03-conflict-detection.md` — Escenarios 1-6
- `specs/04-skalling-forget-consolidation.md` — Escenarios 1-8
- `specs/05-doctor-memory-section.md` — Escenarios 1-8

---

**Próximo paso**: una vez aprobado el design, `tasks.md` desglosa las 24 tareas para Teo.
