---
name: skalling-routing
description: "Clasificar intención, impacto, riesgo y decisiones humanas antes de delegar cambios."
license: MIT
metadata:
  author: skalling-team
  version: "2.0"
---

# Routing por evidencia

Alex clasifica antes de delegar. Para código, la única clasificación que autoriza
implementar es `skalling_workflow start`: el motor aplica las reglas de
`skalling_classify.py` (las mismas que `skalling-route.sh`), registra la ruta y
las métricas, y el guard solo deja delegar a Teo cuando ESE workflow está en
`implementation_ready`. Ni el motor ni el script interpretan el texto del
pedido: Alex aporta la evidencia.

1. Distinguir explicación, auditoría e implementación. Explicar y auditar no autorizan cambios.
2. Consultar contexto mínimo e impacto. Si se desconoce, investigar con Jes/CodeGraph antes de implementar.
3. Detectar áreas sensibles (auth, permisos, pagos, datos persistidos, secretos, infraestructura, CI/CD), contratos, arquitectura, costes, UI y alcance transversal. Todo cambio de estilos marca `visual`.
4. Ante una decisión crítica pendiente, Alex presenta 2–3 opciones, consecuencias y recomendación al usuario y espera su respuesta. `start` rechaza `decision: pending` y `clarity: ambiguous`: no hay forma de implementar antes.
5. Clasificar y comunicar ruta, motivo y fases omitidas.

| Evidencia | Ruta | Equipo |
|---|---|---|
| Local, claro, reversible, sin área sensible ni decisión pendiente | FAST-TRACK | Alex → Teo + verificación automática del proyecto (Jhon si no hay comando configurado) |
| Cambio acotado de módulo/contrato conocido, riesgo medio | INLINE | Alex → Sol → Teo → Jhon |
| Feature grande/nueva de alcance medio-alto, flujo transversal, arquitectura, seguridad, datos, CI/CD o ambigüedad material | SDD | Alex → Pol → Sol → Teo → Jhon → Luz → Pau |
| Solo investigación/explicación | RESEARCH | Alex → Jes |
| Solo auditoría | DIRECT | Alex → Luz |

Pol aclara alcance y aceptación (`clarify`); Sol persiste plan/tasks y marca
`ready` con el plan aprobado; Teo implementa y entrega (`deliver`); Jhon verifica
(`oracle`, `check`, `approve`/`reject`); Luz revisa riesgos en alto; Pau documenta
(`document`); Alex cierra (`complete`, que sella la aprobación para Git).
No convocar a todos para una corrección pequeña, pero preservar los controles del riesgo.

## Clasificación ejecutable

Código (herramienta `skalling_workflow`, `action: "start"`):

```json
{"id": "req-boton-104512", "risk": "low", "scope": "local", "clarity": "clear", "decision": "none",
 "files": ["app/components/Button.tsx"], "acceptance": "El botón dice 'Guardar'",
 "reuse": "Componente Button existente", "intent": "Corregir texto de botón"}
```

Reclasificar un pedido ya empezado: mismo formato con `"supersedes": "<id anterior>"`
(solo ese pedido queda `superseded`; los de otras sesiones no se tocan).
Task de un plan: `"task": "<plan-slug>/<task-slug>"`.

Investigación o auditoría (sin workflow):

```bash
skalling-route.sh classify --kind research --risk low --record --intent "Explicar login" --project "$PWD"
```

- `scope`: local, module o cross-cutting (con alcance desconocido no hay start: investigar primero).
- `decision`: none, pending o resolved; resolved exige respuesta real del usuario.
- `sensitive`: cualquiera de las áreas sensibles anteriores (→ high).
- `visual`: exige el concepto `design-system`; NO sube el riesgo por sí solo.

`start` exige: proyecto con contexto inicial (si no, ruta DISCOVERY), resumen del
proyecto en TeamDB, archivos existentes, aceptación observable y estrategia de
reutilización. Medium/high: Sol marca `ready` solo con `plan_id` de un plan
aprobado con diseño. No fabricar evidencia para pasar un requisito.

## Reevaluación

Reevaluar al descubrir impacto, riesgo o ambigüedad nuevos, sin esperar porcentajes
ni varios rechazos. Teo devuelve ROUTE_REASSESSMENT_REQUIRED si el atajo no se sostiene.
No rebajar riesgo por coste de tokens, urgencia, cantidad de archivos o la palabra fix.

Ejemplos: texto de botón → FAST-TRACK; ordenamiento de módulo conocido → INLINE;
validación de sesión/login → SDD por seguridad; rehacer pedidos → SDD aunque sean
dos archivos; explicar login → RESEARCH sin cambios.

## Publicación y autoridad

Push y deploy desautorizados por defecto. Requieren permiso explícito del usuario
en esta sesión para el alcance y destino. Un permiso puntual anterior no se reutiliza;
uno para toda la sesión vale dentro de su alcance hasta revocación. Implementar,
terminar, aprobar plan, tests o commit no autoriza publicación. Si pidió revisar
antes, esperar su aprobación del resultado. La delegación transporta cita y alcance
del permiso; los agentes no lo crean. Trabajo independiente puede continuar mientras
una decisión humana sigue pendiente.
