# Spec 02: Formato declarativo de claims verificables

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

## Bloque canónico

Las specs que quieran participar en drift detection declaran sus checks en una sección de nivel 2 con título exacto:

```markdown
## Verificación

- archivo: agents-base/Alex.md
- count: 8 agentes en agents-base
- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md
```

El bloque comienza en la línea exacta `## Verificación` y termina al llegar al siguiente heading de nivel 2 (`## `) o al final del archivo. El contenido fuera de ese bloque no constituye claims.

---

## Gramática exacta

### Claim `archivo`

```text
- archivo: <ruta-relativa>
```

Ejemplo válido:

```markdown
- archivo: scripts/mem-review.sh
```

Semántica: `<ruta-relativa>` identifica un archivo regular bajo la raíz actual del repositorio.

### Claim `count`

```text
- count: <entero-no-negativo> <etiqueta> en <ruta-relativa-de-directorio>
```

Ejemplo válido:

```markdown
- count: 8 agentes en agents-base
```

Semántica: el entero esperado se compara con la cantidad de archivos regulares ubicados directamente en el directorio. `<etiqueta>` es texto descriptivo no vacío para el reporte; puede contener espacios, pero no la secuencia separadora ` en `.

### Claim `contiene`

```text
- contiene: "<texto-literal-no-vacío>" en <ruta-relativa-de-archivo>
```

Ejemplo válido:

```markdown
- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md
```

Semántica: el archivo debe contener el texto literal, con coincidencia case-sensitive. En el MVP, `<texto-literal-no-vacío>` MUST caber en una sola línea y no puede contener comillas dobles escapadas; si se necesita buscar una comilla doble, el claim queda fuera de la gramática del MVP.

---

## Escenario 1: Sección reconocida

**Given** una spec con el heading exacto `## Verificación`
**When** el parser la recorre
**Then** MUST evaluar bullets reconocidos hasta el siguiente heading `## ` o EOF.

**Given** headings como `### Verificación`, `## verificación` o `## Verificaciones`
**When** el parser los recorre
**Then** MUST ignorarlos como bloques de claims.

---

## Escenario 2: Paths válidos

**Given** un claim reconocido
**When** se parsea su path
**Then** el path MUST ser relativo a la raíz del repositorio
**And** MUST usar `/` como separador
**And** MUST ser no vacío
**And** no puede comenzar con `/`, `~` ni contener un segmento `..`.

Los paths con espacios no forman parte del MVP. Un path inválido MUST producir un error de formato y exit code final `1`, no ser ignorado silenciosamente.

---

## Escenario 3: Bullets no reconocidos

**Given** texto narrativo u otros bullets dentro de `## Verificación`
**When** una línea no empieza exactamente por `- archivo:`, `- count:` o `- contiene:`
**Then** el parser MAY ignorarla.

**Given** una línea que sí empieza por uno de esos prefijos
**But** no cumple su gramática exacta
**When** se procesa
**Then** MUST reportarse como claim malformado
**And** el resultado global MUST fallar.

Esto evita que un typo en un claim aparente estar verificado cuando nunca se ejecutó.

---

## Escenario 4: Duplicados

**Given** dos líneas idénticas de claim, en la misma spec o en specs distintas
**When** corre drift detection
**Then** cada aparición MUST evaluarse y reportarse por separado.

El MVP no deduplica claims porque cada línea pertenece al contrato documental de su spec.

---

## Reglas MUST

1. El heading MUST escribirse exactamente `## Verificación`.
2. Cada claim MUST ocupar una única línea y comenzar en columna 1 con `- `.
3. Las claves MUST ser minúsculas y exactas: `archivo`, `count`, `contiene`.
4. Debe existir un único espacio después de `:` en los ejemplos canónicos; el parser MUST aceptar al menos ese formato y no necesita normalizar variantes.
5. Todos los paths MUST ser relativos, permanecer dentro del repositorio y carecer de espacios.
6. `count` MUST usar un entero decimal no negativo y el separador literal ` en `.
7. `contiene` MUST encerrar el texto en comillas dobles y usar el separador literal ` en ` después de la comilla de cierre.
8. La búsqueda de `contiene` MUST ser literal y case-sensitive.
9. Una línea con prefijo conocido pero sintaxis inválida MUST causar fallo global.
10. La ausencia total de claims válidos en todas las specs MUST causar exit code `1`.

## Reglas SHOULD

1. Las specs SHOULD declarar solo claims estables y valiosos para futuros planes, no detalles incidentales.
2. La etiqueta de `count` SHOULD describir claramente qué representa el número, aunque no altere el conteo.
3. El texto de `contiene` SHOULD ser suficientemente distintivo para evitar falsos positivos por coincidencias casuales.
4. Las rutas SHOULD apuntar a artefactos versionados del repositorio.

## Ejemplos inválidos

```markdown
- Archivo: agents-base/Alex.md
- archivo: /tmp/Alex.md
- archivo: ../otro-repo/secreto.md
- count: ocho agentes en agents-base
- count: 8 en agents-base
- contiene: SINCRONIZADO CON: en agents-base/Alex.md
- contiene: "" en agents-base/Alex.md
- contiene: "texto" en ruta con espacios/archivo.md
```

Los prefijos con capitalización distinta no se reconocen; los prefijos conocidos con sintaxis rota producen error. Los paths absolutos, traversal y espacios son inválidos.

## Criterios de aceptación

- [ ] Los tres ejemplos canónicos se parsean sin ambigüedad.
- [ ] El parser distingue contenido narrativo de claims ejecutables.
- [ ] Un typo después de un prefijo reconocido no pasa silenciosamente.
- [ ] Ningún claim puede escapar de la raíz del repositorio.
- [ ] El formato puede escribirse manualmente sin YAML, JSON ni dependencias adicionales.

## Out of Spec

- YAML frontmatter para claims.
- Claims multilinea.
- Comillas escapadas dentro de `contiene`.
- Paths con espacios, globbing o variables de entorno.
- Operadores booleanos, negación o composición de claims.
- Claims semánticos o relaciones entre funciones.
