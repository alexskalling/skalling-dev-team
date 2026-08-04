# Spec 01: Detección de concept docs afectados por un plan

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Interfaz del detector

Uso canónico invocado por Pau antes del `git mv` del archivado:

```bash
bash scripts/spec-memory-link.sh <directorio-del-plan>
```

El único argumento posicional es el path al directorio raíz del plan que contiene `proposal.md`, `design.md`, `tasks.md` y un subdirectorio `specs/`. El script resuelve la raíz del repositorio desde su propia ubicación y devuelve, en stdout, un listado de concept docs únicos que requieren footer.

Los concept docs detectados son PASADOS al módulo de aplicación de footer (definido en la Spec 02). Este spec cubre solo la **detección**.

---

## Escenario 1: Archivos escaneados

**Given** un plan en `<directorio-del-plan>/` con `proposal.md`, `design.md`, `tasks.md` y `specs/*.md`
**When** el script corre el detector
**Then** MUST escanear, en este orden:
  1. `<directorio-del-plan>/proposal.md`
  2. `<directorio-del-plan>/design.md`
  3. `<directorio-del-plan>/tasks.md`
  4. `<directorio-del-plan>/specs/*.md` (cada archivo, en orden lexicográfico)

**And** MUST NO escanear:
  - `<directorio-del-plan>/receipts/` ni nada bajo él.
  - `index.md` que pueda existir como auxiliar.
  - Cualquier archivo fuera de los cuatro tipos listados.

**And** si alguno de los tres archivos principales (`proposal.md`, `design.md`, `tasks.md`) no existe, MUST tratarlo como archivo vacío y continuar.

---

## Escenario 2: Patrón de búsqueda

**Given** un archivo escaneado
**When** el detector lo recorre
**Then** MUST extraer toda línea que coincida con el regex:

```text
\.opencode/context/concept/[A-Za-z0-9._-]+\.md
```

**And** MUST aceptar el path con o sin slash inicial.
**And** MUST aceptar el path con o sin anclaje a la raíz del repo (i.e., `.opencode/...` y `repo/.opencode/...` son ambos válidos).
**And** MUST NO interpretar el texto como nada más: no es Markdown link, no es código, no es backtick. Es texto crudo donde aparece el patrón.

**And** MUST descartar cualquier match que:
  - Contenga segmentos `..` (path traversal).
  - Contenga espacios.
  - Sea igual a `.opencode/context/concept/.md` (nombre de archivo vacío).

---

## Escenario 3: Deduplicación

**Given** varios archivos escaneados que mencionan el mismo concept doc (ej: aparece en `proposal.md` y también en `design.md`)
**When** el detector termina
**Then** MUST emitir el concept doc una sola vez en el output.

**And** MUST NO preservar el orden de primera aparición entre archivos distintos; emite en orden lexicográfico sobre el path del concept doc para que el output sea determinista.

---

## Escenario 4: Validación del concepto encontrado

**Given** un match extraído por el regex
**When** el detector lo procesa
**Then** MUST verificar que el archivo concept doc existe en el filesystem del repo:

```text
$RAIZ_REPOSITORIO/.opencode/context/concept/<slug>.md
```

**And** si el archivo NO existe, MUST reportar el match como `referencia-rota` por stderr en formato:

```text
advertencia: referencia a concept doc inexistente: <path-relativo> (en <archivo-del-plan>)
```

**And** MUST NO agregarlo a la lista de concept docs a los que se les aplicará el footer (continúa con los demás).

**And** MUST continuar procesando aunque haya referencias rotas; el reporte de advertencias no aborta el script.

---

## Escenario 5: Errores de entrada

**Given** cualquiera de estas condiciones:
  - falta el argumento;
  - se reciben más argumentos posicionales;
  - el directorio del plan no existe o no es directorio;
  - el directorio no contiene `proposal.md`, `design.md` NI `tasks.md` (al menos uno debe existir para que tenga sentido procesar);
  - el directorio no contiene `specs/` Y tampoco hay `proposal.md`/`design.md`/`tasks.md` (ningún archivo escaneable);

**When** se ejecuta el CLI
**Then** MUST imprimir un error accionable a stderr
**And** MUST terminar con exit code `1`.

---

## Escenario 6: Sin concept docs afectados

**Given** un plan válido pero ninguno de los archivos escaneados contiene el patrón
**When** el detector corre
**Then** MUST imprimir un mensaje informativo por stdout:

```text
spec-memory-link: 0 concept docs afectados por este plan
```

**And** MUST terminar con exit code `0`.

---

## Escenario 7: Salida del detector

**When** hay uno o más concept docs afectados
**Then** el detector MUST imprimir, una línea por concept doc, el path relativo al repo:

```text
.opencode/context/concept/repo-pattern.md
.opencode/context/concept/repository-pattern.md
```

**And** MUST terminar con exit code `0`.

Este output es consumible por el módulo de aplicación de footer (Spec 02). En el MVP, ambos módulos viven en el mismo script; la separación es lógica para que Spec 02 pueda testear el componente de aplicación con una lista hardcoded.

---

## Reglas MUST

1. El script MUST existir en `scripts/spec-memory-link.sh` con `#!/usr/bin/env bash` y `set -euo pipefail`.
2. MUST ser portable con Bash 3.2; no puede usar `declare -A`, `mapfile`, `readarray` ni otras APIs exclusivas de Bash 4+.
3. MUST aceptar exactamente un argumento posicional.
4. MUST resolver la raíz del repositorio desde su propia ubicación, no desde el current working directory del invocador.
5. MUST escanear solo `proposal.md`, `design.md`, `tasks.md` y `specs/*.md`; no debe leer `receipts/`, `index.md` auxiliares ni nada más.
6. MUST usar el regex exacto `\.opencode/context/concept/[A-Za-z0-9._-]+\.md` para detectar matches.
7. MUST deduplicar los matches preservando solo la primera aparición en orden lexicográfico.
8. MUST verificar que cada concept doc detectado existe en el filesystem antes de devolverlo.
9. MUST reportar las referencias rotas por stderr con prefijo `advertencia:` y no incluirlas en la lista de footer.
10. Los identificadores propios MUST estar en español (R1). Ejemplos: `detectar_concept_docs`, `extraer_matches`, `validar_path_concept`, `validar_argv`.
11. El script MUST NO modificar ningún archivo del repositorio en su fase de detección; la fase de modificación es exclusiva de la Spec 02.
12. Cualquier commit asociado MUST tener mensaje en español conforme a R16.

## Reglas SHOULD

1. SHOULD usar `grep -E` o `awk` para la extracción; no SHOULD depender de `pcregrep` ni Perl.
2. SHOULD imprimir el output agrupado por carpeta del plan (primero `proposal.md`, luego `design.md`, etc.) para que un humano que inspeccione el log entienda el orden.
3. SHOULD limitar la longitud del archivo escaneado para evitar falsos positivos en archivos grandes (límite sugerido: 10 MB).
4. SHOULD emitir colores solo cuando el output sea una terminal.

## Criterios de aceptación

- [ ] El script acepta exactamente un path y rechaza cero, dos o más argumentos.
- [ ] El detector procesa solo los cuatro tipos de archivo listados.
- [ ] El regex detecta referencias con y sin slash inicial, con y sin anclaje a la raíz.
- [ ] El regex rechaza paths con `..`, con espacios o con nombre de archivo vacío.
- [ ] Los concept docs duplicados se enumeran una sola vez.
- [ ] Las referencias a archivos inexistentes se reportan por stderr y se descartan.
- [ ] Un plan sin concept docs afectados termina con mensaje informativo y exit code `0`.
- [ ] Un plan con concept docs afectados termina con la lista de paths y exit code `0`.
- [ ] La implementación pasa `bash -n scripts/spec-memory-link.sh`.
- [ ] El script no contiene `declare -A`, `mapfile` ni `readarray`.

## Out of Spec

- Detección semántica (interpretación de prosa).
- Concept docs en `decisiones/`, `preferencias/`, `problemas-conocidos/`, `contexto/`.
- Búsqueda de menciones indirectas (ej: "el ADR sobre repository pattern").
- Detección por diff entre commits.
- Cualquier heurística que escape al regex declarado.
- Modificación de archivos del repositorio (esa es la Spec 02).

## Verificación

```markdown
## Verificación

- archivo: scripts/spec-memory-link.sh
- contiene: "concept" en scripts/spec-memory-link.sh
- contiene: "detectar_concept_docs" en scripts/spec-memory-link.sh
```
