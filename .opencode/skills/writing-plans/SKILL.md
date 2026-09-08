---
name: writing-plans
description: Preparar un plan ejecutable en TeamDB, proporcional al riesgo y al alcance autorizado.
license: MIT
metadata:
  author: skalling-team
  version: "3.0"
---

# Planificación de Skalling

La fuente canónica es `.opencode/context/team.db`; los helpers siguientes escriben allí.

Sol persiste planes. Pol aclara producto y Alex coordina. Seguir skalling-routing
para escoger el flujo; no crear atajos ni nuevas rondas de aprobación por esta skill.

## Antes de planificar

Leer el pedido, decisiones pertinentes y archivos existentes. Identificar qué se
reutiliza, qué cambia, criterios de aceptación y riesgos. Una ruta no sustituye
leer el código. Resolver decisiones críticas con Alex; no inventar la respuesta.
Un cambio pequeño necesita un plan pequeño, no tareas artificiales por minutos.

## Crear y aprobar

Pasar las tareas por stdin; no crear tasks.md temporales en el proyecto.

```bash
printf '%s\n' '- [ ] Implementar el comportamiento acordado' |
bash "$SKALLING_ROOT/scripts/teamdb-plan.sh" "$PWD" "<slug>" "<Título descriptivo>" - \
  --by=sol --purpose="<motivo>" --acceptance="<resultado verificable>" --strict-contract
```

Consultar el plan_id devuelto o recuperarlo mediante teamdb-read.sh.
Completar el diseño real y registrar la referencia al alcance/aprobación del usuario:

```bash
bash "$SKALLING_ROOT/scripts/teamdb-plan-approve.sh" "$PWD" "<plan_id>" \
  "<diseño y componentes reutilizados>" "<aceptación>" "<referencia real al pedido aprobado>"
```

## Ajustar y consultar

Los comandos aceptados son:

```bash
bash "$SKALLING_ROOT/scripts/teamdb-amend.sh" "<slug>" --add-task="<Título>" \
  --purpose="<motivo>" --acceptance="<criterio>" --by=sol "$PWD"
bash "$SKALLING_ROOT/scripts/teamdb-amend.sh" "<slug>" --show "$PWD"
bash "$SKALLING_ROOT/scripts/teamdb-execute-plan.sh" "<slug>" "$PWD"
```

execute-plan descubre la siguiente tarea; no implementa código. No inventar
--slug, --design-stdin ni --dry-run para estos comandos.
Cada tarea conserva propósito, aceptación y dependencias. No reemplazar una tarea
activa o terminada; crear una sucesora usando los helpers.

## Entrega

Sol devuelve plan_id, feature-slug, archivos, diseño, aceptación y riesgos a Alex.
Alex confirma el routing y entrega a Teo el contexto concreto.
No copiar código entero al plan si basta referenciar y explicar la modificación.
No exportar Markdown ni crear commits como pasos automáticos.
Solo cuando el usuario pida una exportación legible:

```bash
bash "$SKALLING_ROOT/scripts/teamdb-export-md.sh" "$PWD" --plan="<slug>"
```

Commit, push y deploy mantienen el consentimiento definido por el usuario.
