# Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto

**Slug:** agentes-db-primera-2026-08-06
**Status:** approved
**Agent:** pol
**Fecha:** 2026-08-06 13:19:03

## Contexto

Hoy cuando un usuario pide un plan, los agentes Alex/Pol/Sol/Teo leen 5-10 archivos del proyecto para entender qué existe, en lugar de consultar la tabla concepts de team.db. Aunque hay una regla soft en constitución R14 "consultá la DB primero", no se enforce.

## Causa raíz

Los agentes LLMs ignoran instrucciones narrativas cuando tienen un read/grep tentador disponible. La DB requiere esfuerzo explícito (`teamdb-search.sh "<query>"`), leer un archivo requiere 1 click.

## Decisión

Reemplazamos la sección soft "Grafos del proyecto — cómo y cuándo consultarlos" en los 4 agentes del ciclo SDD (Alex, Pol, Sol, Teo) por un **protocolo numerado concreto**:

1. **Pasos bash numerados**: Paso 1 = `bash teamdb-search.sh "<query>" concept|decision`, Paso 2 = leer `teamdb-related.sh` de slugs relevantes, Paso 3 (opcional) = `curl /api/codegraph`.
2. **Regla de oro**: si la DB alcanzó, NO leer más.
3. **CITA obligatoria**: en el artefacto/handoff (proposal.md, tasks.md, commit), el agente debe citar textualmente el resultado de la consulta DB (cuántos concepts, cuántos decisions, qué encontró).

## Tasks completadas

- [x] Reescribir sección de cada agente con protocolo numerado (Teo, 4 agentes)
- [x] Agregar test FIX 1.3 con 12 asserts en setup.test.sh (Teo)
- [x] Sincronizar agentes a ~/.config/opencode/agents/ (Teo)
- [x] Inicializar team.db en meta-proyecto (con backup + dry-run)
- [x] Persistir propuesta en DB (este INSERT)

## Consecuencias

### Positivas
- Ahorro de tokens estimado: 60-75% por plan
- Consistencia: el sistema usa la memoria que ya documentamos
- Tests verifican que cada agente tiene el protocolo (12 asserts FIX 1.3)

### Negativas / Riesgos
- Si la DB está vacía, los agentes igualmente intentan leer código (esperado, es el fallback)
- Tests no garantizan que el LLM siga el protocolo al pie de la letra (es soft-enforcement)
- Hay 3 menciones de superpowers:* restantes en systematic-debugging/SKILL.md que requieren evaluación caso por caso
