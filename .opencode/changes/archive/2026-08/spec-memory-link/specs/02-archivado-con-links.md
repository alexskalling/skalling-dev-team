# Spec 02: Archivado con links — integración en Pau.md y aplicación del footer

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Punto de integración en Pau

Pau es la única que escribe memoria definitiva y la única que ejecuta el script `scripts/spec-memory-link.sh` como parte de su flujo de archivado. La integración ocurre en **PASO 5 — Archivo los changes completados** de `agents-base/Pau.md`.

Pau NO rompe su flujo actual. Solo agrega un sub-paso explícito antes del `mv`/`git mv`.

---

## Escenario 1: Nuevo sub-paso en PASO 5

**Given** Pau llegó a PASO 5 con Quality Gate PASSED de Luz, documentación pública terminada y concept docs válidos
**When** Pau ejecuta el sub-paso de link a spec
**Then** MUST calcular el path final del plan archivado:

```text
.opencode/changes/archive/<YYYY-MM>/<slug-del-plan>/
```

donde `<YYYY-MM>` es el mes del archivado en formato `YYYY-MM` y `<slug-del-plan>` es el nombre del directorio actual del plan.

**And** MUST invocar:

```bash
bash scripts/spec-memory-link.sh <directorio-del-plan> <path-archivo-final>
```

El segundo argumento es el path final (post-archivado) que se usará como destino del link en el footer. Así Pau puede pasar el path correcto antes de hacer el `mv`.

**And** MUST esperar la salida del script (exit code `0` indica éxito) y proceder con el `git mv` solo si el script terminó OK.

**And** MUST reportar al usuario, al final del PASO 5, qué concept docs recibieron el footer:

```text
Concept docs enlazados a este plan:
- .opencode/context/concept/repo-pattern.md
- .opencode/context/concept/repository-pattern.md
```

(si la lista está vacía, omitir la sección).

---

## Escenario 2: Formato del footer

**Given** un concept doc que NO tiene `## Spec original` todavía
**When** el script aplica el footer
**Then** MUST append al final del archivo (después de cualquier contenido existente, incluido un trailing newline) el siguiente bloque:

```markdown


## Spec original

[.opencode/changes/archive/<YYYY-MM>/<slug>/](.opencode/changes/archive/<YYYY-MM>/<slug>/)
```

**Reglas de formato**:
- Una línea en blanco antes del heading `## Spec original` (separación visual estándar de Markdown).
- El texto del link es idéntico al target (link a la carpeta del plan archivado).
- El path es **relativo al concept doc** (no absoluto). Para un concept doc en `.opencode/context/concept/`, el path relativo es `../../changes/archive/<YYYY-MM>/<slug>/`.

**And** MUST preservar el trailing newline del archivo original (no agrega líneas vacías extra al final).

**And** MUST NO modificar el frontmatter YAML ni ninguna sección anterior del concept doc.

---

## Escenario 3: Idempotencia — ya tiene footer

**Given** un concept doc que YA tiene un heading `## Spec original` (regex `^## Spec original$` en cualquier parte del archivo)
**When** el script intenta aplicarle el footer
**Then** MUST NO modificar el archivo.
**And** MUST emitir por stdout, en la lista de resultados, una línea con prefijo `preservado:`:

```text
preservado: .opencode/context/concept/repo-pattern.md (ya enlazado)
```

**And** MUST seguir procesando los demás concept docs.

**Justificación**: la regla "`## Spec original` lleva el link al plan que originó el concept doc" significa que el primero es la fuente de verdad. Planes subsiguientes que toquen el mismo doc no deben sobrescribir la evidencia histórica.

---

## Escenario 4: Cálculo del link relativo

**Given** el path del concept doc: `.opencode/context/concept/<slug>.md`
**And** el path destino del plan: `.opencode/changes/archive/<YYYY-MM>/<slug-del-plan>/`
**When** el script construye el link
**Then** MUST generar el path relativo correcto usando una función propia (sugerida: `calcular_path_relativo`).

**Algoritmo**:
1. Tomar el directorio del concept doc: `.opencode/context/concept/`.
2. Tomar el directorio destino del plan: `.opencode/changes/archive/<YYYY-MM>/<slug-del-plan>/`.
3. Calcular la mínima secuencia de `../` necesaria para ascender desde el directorio del concept doc hasta el ancestro común (la raíz del repo).
4. Concatenar con el path destino del plan.

**Implementación portable**: usar `python3` no es aceptable; implementar en Bash 3.2 con `awk`/`sed`/`cd`/`pwd` está OK. Si el cálculo es complicado, una alternativa válida es hardcodear que el concept doc siempre está a `../../` del directorio del plan (porque el plan siempre vive en `.opencode/changes/...` y el concept doc en `.opencode/context/concept/`). Esa es la realidad del MVP y debe documentarse como asunción en `scripts/spec-memory-link.sh`.

---

## Escenario 5: Permisos y edges

**Given** Pau ejecuta el script
**When** se aplica el footer
**Then**:
- Si el concept doc no existe en el filesystem (raro: el detector ya filtró, pero defensa en profundidad): MUST reportar error accionable y continuar con el resto.
- Si el concept doc no es escribible: MUST reportar `error: no se puede escribir <path>` y continuar con el resto.
- Si el concept doc es vacío (cero bytes): MUST tratarlo como error de formato y reportarlo, NO appendar el footer a un archivo vacío.

**And** en todos los casos de error por archivo individual, MUST NO abortar el batch; el script procesa los demás y reporta al final.

---

## Escenario 6: Reporte consolidado

**Given** el script terminó de procesar todos los concept docs
**When** imprime el resumen
**Then** MUST listar en stdout:
  - Los concept docs a los que se les aplicó el footer (prefijo `aplicado:`).
  - Los concept docs preservados por idempotencia (prefijo `preservado:`).
  - Los errors por archivo (prefijo `error:`).

**And** MUST terminar con exit code `0` si al menos un concept doc fue procesado o preservado (éxito parcial), Y exit code `1` si ningún concept doc fue procesado NI preservado Y el detector no devolvió candidatos.

**Justificación del exit code**: si el script recibe una lista vacía, devolver `0` sería mentir ("no hizo nada pero OK"). Devolver `1` indica que no hubo trabajo real. Si la lista tenía candidatos y todos fallaron, también `1`.

---

## Escenario 7: Estructura del PASO 5 modificada

**Given** el contenido actual de `agents-base/Pau.md` PASO 5 (líneas 177-188)
**When** se agrega la integración
**Then** MUST quedar un sub-paso explícito, **antes** del `git mv`:

```markdown
### PASO 5 — Archivo los changes completados (ownership de archive)

Al cierre del ciclo (Luz PASSED + documentación terminada + concept docs validados):

1. **Enlazar concept docs a la spec** (cuando aplique): corro `bash scripts/spec-memory-link.sh <dir-origen> <dir-destino>` antes de mover la carpeta. El script agrega el footer `## Spec original` a cada concept doc afectado, con link relativo al path final del plan archivado. Si el script falla, pauso y notifico al usuario.

2. **Muevo el change completado**: `[origen] → .opencode/changes/archive/<YYYY-MM>/[destino]/`
   ...
```

**And** MUST NO eliminar ni reordenar nada del PASO 5 existente; solo se inserta el sub-paso de link.

**And** MUST NO modificar permisos del frontmatter de Pau (los permisos `edit: .opencode/context/**/*.md: allow` y `edit: .opencode/changes/**: allow` ya cubren lo necesario).

**And** MUST NO agregar nuevas dependencias a Pau.md (no requiere skills nuevas, no requiere permisos nuevos).

---

## Reglas MUST

1. El script `scripts/spec-memory-link.sh` MUST extender el sub-módulo de detección (Spec 01) con un sub-módulo de aplicación de footer.
2. Ambos sub-módulos MUST vivir en el mismo script en el MVP; la separación es lógica, no física.
3. El footer MUST ser exactamente el bloque declarado en Escenario 2, con un newline simple de separación antes del heading.
4. La función de aplicación MUST NO sobrescribir un footer `## Spec original` existente.
5. La función de aplicación MUST preservar el contenido original del concept doc (frontmatter, secciones, trailing newline).
6. Pau MUST invocar el script antes del `git mv` del plan.
7. Pau MUST reportar al usuario la lista de concept docs enlazados al finalizar PASO 5.
8. Si el script devuelve exit code distinto de `0`, Pau MUST pausar el archivado y notificar al usuario.
9. Los paths en el footer MUST ser relativos al concept doc, no absolutos.
10. El cálculo del path relativo MUST ser portable con Bash 3.2 sin usar `python3` ni `realpath` (que no es POSIX).
11. Pau.md MUST mantener intacta toda la documentación existente en PASO 5; el sub-paso se inserta, no reemplaza.
12. Identificadores en español (R1), cero comentarios en código (R2), commits en español (R16).

## Reglas SHOULD

1. SHOULD usar `printf '%s\n'` para construir el bloque del footer, evitando `echo` con caracteres de escape.
2. SHOULD registrar el resultado en log append-only del proyecto (si existe `.opencode/context/log.md`) con la fecha y la lista de concept docs afectados.
3. SHOULD validar que el concept doc tiene las 4 secciones (`What`, `Why`, `Where`, `Learned`) si fue creado después del deploy de memory-improvements Fase 1, y rechazar el append si no las tiene (mantiene coherencia con PASO 4 de Pau).

## Criterios de aceptación

- [ ] El footer generado tiene exactamente el formato del Escenario 2.
- [ ] Un concept doc sin `## Spec original` recibe el footer.
- [ ] Un concept doc con `## Spec original` existente NO se modifica.
- [ ] El frontmatter YAML del concept doc queda intacto.
- [ ] El path del link es relativo al concept doc.
- [ ] Pau invoca el script antes del `git mv` y reporta la lista al usuario.
- [ ] Pau.md sigue teniendo intacto el resto del PASO 5.
- [ ] Pau.md no tiene permisos nuevos.
- [ ] El script maneja errores de escritura por archivo individual sin abortar el batch.
- [ ] El summary final tiene el formato del Escenario 6.

## Out of Spec

- Sincronización bidireccional (spec → concept doc).
- Reescritura del footer existente (la regla es preservar el primero).
- Validación de que el link sigue vivo (eso es drift detection).
- Inserción del footer en una posición distinta al final del archivo.
- Detección de concept docs fuera de `.opencode/context/concept/`.
- Auto-invocación del script (Pau debe llamarlo manualmente).

## Verificación

```markdown
## Verificación

- contiene: "spec-memory-link" en agents-base/Pau.md
- contiene: "Spec original" en agents-base/Pau.md
- archivo: scripts/spec-memory-link.sh
```
