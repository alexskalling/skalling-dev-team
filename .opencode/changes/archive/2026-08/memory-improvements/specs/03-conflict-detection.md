# Spec: Detección de conflictos antes de aprobar un plan

> **Status**: Draft
> **Mejora**: #3 de memory-improvements
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

---

## Escenario 1: Pol escribe un proposal que NO contradice memoria existente

**Given** que Pol está cerrando el `proposal.md` de un nuevo feature SDD
**When** Pol revisa el bundle OKF (`.opencode/context/decisiones/`, `.opencode/context/preferencias/`, `.opencode/context/problemas-conocidos/`) buscando concept docs relevantes al feature
**Then** Pol MUST confirmar que no hay contradicciones
**Y** Pol MUST agregar al final del `proposal.md`, antes del `## Stakeholders`, una sección:
```markdown
## ✅ Sin conflictos con memoria existente
- Revisado: YYYY-MM-DD
- Áreas consultadas: decisiones/, preferencias/, problemas-conocidos/
- Concept docs relevantes leídos: [lista con paths]
```

---

## Escenario 2: Pol detecta contradicción con una decisión pasada

**Given** que Pol está cerrando el `proposal.md` y encuentra un concept doc en `.opencode/context/decisiones/` que contradice la propuesta
**When** Pol detecta la contradicción
**Then** Pol MUST agregar al final del `proposal.md`, antes del `## Stakeholders`, una sección:
```markdown
## ⚠️ Conflictos detectados
- **Concept doc contradicho**: [path al .opencode/context/decisiones/...]
- **Razón de contradicción**: [explicación concreta — qué dice el concept doc vs qué propone la feature]
- **Propuesta de resolución**: [opción A: actualizar el concept doc con supersedes / opción B: cambiar la feature / opción C: explayar ambas y dejar al usuario decidir]
```
**Y** Pol MUST escalar a Alex para presentar el conflicto al usuario con opciones (no decide Pol por sí mismo)

---

## Escenario 3: Pol detecta contradicción con un workaround activo

**Given** que Pol está cerrando el `proposal.md` y encuentra un workaround activo en `.opencode/context/problemas-conocidos/` que se vería impactado por la feature
**When** Pol revisa
**Then** Pol MUST agregar el workaround a la sección `## ⚠️ Conflictos detectados` con la misma estructura
**Y** Pol SHOULD proponer en la "Propuesta de resolución" si el workaround queda obsoleto (marcable con `supersedes`) o si debe seguir activo coexistiendo con la feature

---

## Escenario 4: Pol detecta preferencia de equipo contradicha

**Given** que Pol está cerrando el `proposal.md` y encuentra una preferencia en `.opencode/context/preferencias/` (por ejemplo, "estilo de código: TypeScript strict") que la feature relajaría
**When** Pol detecta
**Then** Pol MUST agregar la preferencia a `## ⚠️ Conflictos detectados`
**Y** Pol MUST proponer explícitamente: o se cambia la preferencia con `supersedes`, o se ajusta la feature para cumplirla

---

## Escenario 5: Feature fast-track (Pol NO参与的)

**Given** que Alex clasificó el request como fast-track (cambio trivial, bug obvio) y NO invocó a Pol
**When** Alex maneja el caso directamente
**Then** el chequeo de conflictos NO se aplica formalmente (la sección del proposal no existe porque no hay proposal)
**Y** Alex SHOULD hacer un chequeo visual rápido: si detecta una contradicción obvia con una decisión del bundle, pregunta al usuario antes de derivar a Teo
**Y** si no detecta nada, avanza con el fast-track normalmente

---

## Escenario 6: Bundle OKF vacío o corrupto

**Given** que Pol está por cerrar el `proposal.md` pero `.opencode/context/` está vacío, sin `index.md`, o los archivos no parsean
**When** Pol intenta leer concept docs relevantes
**Then** Pol MUST escalar a Alex: `⚠️ Bundle OKF no legible. No puedo chequear conflictos. Recomiendo correr /skalling-refresh antes de aprobar esta propuesta.`
**Y** Pol NO debe declarar "sin conflictos" si no pudo verificar (preferible bloquear a mentir)

---

## Reglas MUST (obligatorias)

1. Antes de cerrar el `proposal.md`, Pol MUST leer concept docs de `.opencode/context/decisiones/`, `.opencode/context/preferencias/`, `.opencode/context/problemas-conocidos/` cuando estos directorios existan.
2. Pol MUST agregar al `proposal.md` una sección `## ✅ Sin conflictos con memoria existente` o `## ⚠️ Conflictos detectados`. Es OBLIGATORIA — el proposal sin esta sección es inválido.
3. Si hay contradicción, Pol MUST proponer al menos una opción de resolución en cada item de `## ⚠️ Conflictos detectados`.
4. Pol MUST escalar a Alex para presentar conflictos al usuario (Pol no decide solo).
5. La sección de conflictos MUST aparecer antes del `## Stakeholders` y después del `## Success Criteria` (ubicación fija en el proposal).

## Reglas SHOULD (recomendadas)

1. Pol SHOULD leer también `.opencode/context/trabajo-en-curso/` para detectar features activas que se solapen con la propuesta.
2. Pol SHOULD priorizar concept docs con `confidence >= 0.8` y `type: Decision` o `type: Preference` (los de baja confianza o tipo `Context` pueden ignorarse en el chequeo).
3. Pol SHOULD usar `grep -l` o el skill `skalling-routing` para localizar concept docs relevantes por tags/palabras clave antes de leerlos todos (lectura eficiente).
4. Si la lista de concept docs leídos es larga (>10), Pol SHOULD resumirla en el proposal agrupando por área (decisiones / preferencias / workarounds).

## Reglas MAY (opcionales)

1. Pol MAY delegar el chequeo a Jes si el volumen de memoria es muy grande y el contexto lo justifica (Jes es investigadora, puede resumir el bundle).
2. Pol MAY proponer agregar un nuevo concept doc al bundle como parte de la resolución (por ejemplo, "esta feature introduce un nuevo patrón que merece documentarse como `Preference`").
3. El chequeo MAY ser opt-out explícito del usuario si dice "Pol, salteá el chequeo de conflictos esta vez" — pero Pol debe registrar el opt-out en el proposal.

---

## Criterios de Aceptación (resumen)

- [ ] `agents-base/Pol.md` incluye una fase explícita "Chequeo de conflictos" antes de cerrar el proposal.
- [ ] Pol lee concept docs de decisiones/, preferencias/ y problemas-conocidos/ cuando existen.
- [ ] El `proposal.md` finalizado SIEMPRE contiene la sección `## ✅ Sin conflictos` o `## ⚠️ Conflictos detectados`.
- [ ] En un test sintético, Pol detecta una contradicción sembrada y la reporta correctamente.
- [ ] En un test con bundle vacío, Pol NO declara "sin conflictos" — escala el problema.
- [ ] La sección de conflictos aparece antes de `## Stakeholders` y después de `## Success Criteria` (orden fijo).

---

## Out of Spec (explícitamente NO incluido)

- Chequeo automático por script antes de aprobar (la validación es responsabilidad de Pol; convertirla en script es ortogonal — vive en `/skalling-doctor` como mejora #5).
- Validación de conflictos con `trabajo-en-curso/` de OTROS features activos (Pol puede leerlo como SHOULD, pero no se exige parsing formal de dependencias entre features).
- Resolución automática de conflictos (Pol propone opciones; el usuario decide).
- Modificar la constitución para hacer obligatorio el chequeo (es práctica operativa, no regla constitucional).
- Cambios en `Sol.md` para que también haga el chequeo (Sol lee el proposal validado por Pol, no necesita duplicar el chequeo).
- Forzar a Pau a verificar conflictos al documentar (Pau trabaja sobre lo ya aprobado; el chequeo es upstream en Pol).
