# Spec 01: Script principal `scripts/skalling-drift.sh`

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Interfaz CLI

Uso canónico:

```bash
bash scripts/skalling-drift.sh .opencode/changes/archive/2026-08/memory-improvements/
```

El único argumento posicional es el path a la raíz de un plan archivado. El script resuelve la raíz del repositorio desde su propia ubicación y evalúa contra esa raíz todos los paths relativos declarados en claims.

---

## Escenario 1: Invocación válida

**Given** un directorio de plan existente con un subdirectorio `specs/`
**And** `specs/` contiene uno o más archivos `.md`
**When** se ejecuta `bash scripts/skalling-drift.sh <plan>`
**Then** el script MUST leer todos los `.md` ubicados directamente en `<plan>/specs/`, en orden lexicográfico
**And** MUST procesar únicamente los claims válidos dentro de cada sección `## Verificación`
**And** MUST imprimir el archivo de spec y el claim al reportar su resultado.

---

## Escenario 2: Check de existencia

**Given** una spec con `- archivo: agents-base/Alex.md`
**When** ese archivo regular existe bajo la raíz actual del repositorio
**Then** el script MUST reportar `PASS`

**When** el archivo no existe
**Then** MUST reportar `FAIL`
**And** el exit code final MUST ser `1`.

La comprobación corresponde a `[[ -f "$raiz_repo/$ruta" ]]`; un directorio no satisface un claim `archivo`.

---

## Escenario 3: Check de cantidad

**Given** una spec con `- count: 8 agentes en agents-base`
**When** `agents-base/` contiene exactamente 8 archivos regulares en su primer nivel
**Then** el script MUST reportar `PASS`

**When** la cantidad real difiere de 8, o el directorio no existe
**Then** MUST reportar `FAIL`
**And** MUST mostrar la cantidad esperada y la observada.

El sustantivo descriptivo (`agentes`) es texto de reporte y no cambia el algoritmo. El MVP cuenta archivos regulares directamente dentro del directorio indicado, sin recursión y sin filtrar por extensión. El helper propio SHOULD llamarse `contar_archivos`.

---

## Escenario 4: Check de presencia literal

**Given** una spec con `- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md`
**When** el archivo existe y contiene exactamente ese texto en cualquier línea
**Then** el script MUST reportar `PASS`

**When** el archivo no existe o el texto no aparece
**Then** MUST reportar `FAIL`.

La búsqueda MUST ser literal y case-sensitive, equivalente a `grep -Fq -- "$texto" "$archivo"`. No se interpretan expresiones regulares. El helper propio SHOULD llamarse `archivo_contiene`.

---

## Escenario 5: Resultado agregado

**Given** varios claims distribuidos entre varias specs
**When** todos pasan
**Then** el script MUST terminar con exit code `0`

**When** uno o más fallan
**Then** MUST terminar con exit code `1`
**And** MUST seguir procesando los claims restantes para entregar el reporte completo
**And** MUST imprimir un resumen con total, aprobados y fallidos.

---

## Escenario 6: Entrada inválida

**Given** cualquiera de estas condiciones:

- falta el argumento;
- se reciben más argumentos posicionales;
- el plan no existe o no es directorio;
- no existe `<plan>/specs/`;
- `specs/` no contiene archivos `.md`;
- no existe ningún claim reconocido;
- existe una línea con prefijo reconocido pero sintaxis inválida;

**When** se ejecuta el CLI
**Then** MUST imprimir un error accionable a stderr
**And** MUST terminar con exit code `1`.

Los errores de entrada no se confunden con `PASS`; el script no debe declarar una validación exitosa si no verificó ningún claim.

---

## Reglas MUST

1. El archivo MUST existir en `scripts/skalling-drift.sh` y usar `#!/usr/bin/env bash` más `set -euo pipefail`.
2. MUST ser portable con Bash 3.2; no puede usar `declare -A`, `mapfile`, `readarray` ni otras APIs exclusivas de versiones posteriores.
3. MUST aceptar exactamente un path de plan por ejecución.
4. MUST resolver paths de claims desde la raíz del repositorio, no desde el current working directory del invocador.
5. MUST restringir la extracción al bloque `## Verificación` de cada spec y detener ese bloque al encontrar el siguiente heading de nivel 2 (`## `) o al llegar a EOF.
6. MUST soportar únicamente `archivo`, `count` y `contiene` con la gramática de la Spec 02.
7. MUST procesar todos los claims aunque uno falle.
8. MUST retornar `0` solo cuando haya al menos un claim reconocido y todos pasen; cualquier fallo o error de entrada retorna `1`.
9. MUST ser de solo lectura: no modifica specs, código ni archivos del plan.
10. Los identificadores propios MUST estar en español, por ejemplo `verificar_claim`, `contar_archivos`, `archivo_contiene`, `total_aprobados` y `total_fallidos`.
11. Cualquier commit asociado MUST tener mensaje en español conforme a R16.

## Reglas SHOULD

1. SHOULD usar `find "$directorio" -type f -maxdepth 1` de forma compatible con las plataformas soportadas, evitando glob recursivo.
2. SHOULD emitir colores solo cuando el output sea una terminal o permitir desactivarlos, sin que los tests dependan del color.
3. SHOULD mantener funciones separadas para parsear y verificar cada tipo de claim.
4. SHOULD preservar en el reporte el claim original para que el usuario pueda localizarlo y corregir la spec manualmente.

## Criterios de aceptación

- [ ] Un plan válido con los tres tipos de claims puede verificarse desde cualquier current working directory.
- [ ] Cada claim genera exactamente un resultado `PASS` o `FAIL`.
- [ ] Un resultado mixto reporta todos los claims y retorna `1`.
- [ ] Cero claims reconocidos retorna `1`.
- [ ] La implementación pasa `bash -n scripts/skalling-drift.sh` bajo sintaxis compatible con Bash 3.2.
- [ ] El script no modifica el repositorio.

## Out of Spec

- Interpretación semántica de prosa libre.
- Recursión en subdirectorios para `count`.
- Filtros de extensión o patrones glob en `count`.
- Regex, multiline matching o búsqueda case-insensitive en `contiene`.
- Comparación contra revisiones históricas de Git.
- Auto-fix de claims fallidos.
