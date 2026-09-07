---
name: skalling-routing
description: "Clasificar intención, impacto, riesgo y decisiones humanas antes de delegar cambios."
license: MIT
metadata:
  author: skalling-team
  version: "2.0"
---

# Routing por evidencia

Alex clasifica antes de delegar. El script aplica parámetros: NO interpreta el
texto de --intent ni descubre por sí mismo el riesgo.

1. Distinguir explicación, auditoría e implementación. Explicar y auditar no autorizan cambios.
2. Consultar contexto mínimo e impacto. Si se desconoce, investigar con Jes/CodeGraph antes de implementar.
3. Detectar áreas sensibles (auth, permisos, pagos, datos persistidos, secretos, infraestructura, CI/CD), contratos, arquitectura, costes, UI y alcance transversal. Todo cambio de estilos usa `--visual`.
4. Ante una decisión crítica pendiente, Alex presenta 2–3 opciones, consecuencias y recomendación al usuario y espera su respuesta. No responde por el usuario a preguntas de Pol/Sol.
5. Clasificar y comunicar ruta, motivo y fases omitidas.

| Evidencia | Ruta | Equipo |
|---|---|---|
| Local, claro, reversible, sin área sensible ni decisión pendiente | FAST-TRACK | Alex → Teo → Jhon |
| Cambio acotado de módulo/contrato conocido, riesgo medio | INLINE | Alex → Sol → Teo → Jhon |
| Feature grande/nueva de alcance medio-alto, flujo transversal, arquitectura, seguridad, datos, CI/CD o ambigüedad material | SDD | Alex → Pol → Sol → Teo → Jhon → Luz → Pau |
| Solo investigación/explicación | RESEARCH | Alex → Jes |
| Solo auditoría | DIRECT | Alex → Luz |

Pol aclara alcance y aceptación; Sol persiste plan/tasks en TeamDB; Teo implementa;
Jhon verifica; Luz revisa riesgos; Pau conserva conocimiento durable cuando exista.
No convocar a todos para una corrección pequeña, pero preservar los controles del riesgo.

## Clasificación ejecutable

```bash
skalling-route.sh classify --risk low --scope local --clarity clear --decision none --kind code --record --intent "Corregir texto de botón" --project "$PWD"
skalling-route.sh classify --risk high --scope cross-cutting --sensitive --decision pending --record --intent "Cambiar autenticación" --project "$PWD"
```

--scope: local, module, cross-cutting o unknown (default).
--decision: none, pending o resolved; resolved exige respuesta real del usuario.
--clarity: clear o ambiguous. --kind: code, research o audit.
--sensitive: marcar cualquiera de las áreas sensibles anteriores.
--visual: obliga al menos ruta INLINE con Sol y consulta del concepto `design-system`.

Sin `readiness=ready` el resultado es DISCOVERY y no se delega código. Sin alcance comprobado no hay FAST-TRACK. implementation_allowed=false impide
implementar pero permite investigar, preparar plan y opciones. Un true no sustituye
plan/aceptación ni autoriza publicación. Registrar con --record, conservar request_id
y cerrar métricas con skalling-metrics.sh finish. Cada resultado requiere evidencia
real: fuentes, hallazgos o pruebas según intención; nunca inventar receipts.

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
