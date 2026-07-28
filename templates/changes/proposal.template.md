# Proposal: [Nombre corto de la feature]

> **Status**: Draft | Approved | In Progress | Completed | Archived
> **Author**: [agent that wrote it, e.g. Pol]
> **Created**: YYYY-MM-DD
> **Approved**: YYYY-MM-DD (by user)
> **Archived**: YYYY-MM-DD (when moved to archive/)

## Why

[Una o dos oraciones: qué dolor resuelve, para quién, por qué importa AHORA.]

## What Changes

[Bullet list de cambios concretos:
- Agrega X a módulo Y
- Modifica comportamiento de Z
- Introduce nueva dependencia W (con justificación de la escalera de Ponytail)
- etc.]

## Out of Scope

[Qué NO se hace en esta iteración — para evitar scope creep:
- No migrar datos existentes
- No agregar feature de admin
- No internacionalizar
- etc.]

## Rollback Plan

[Cómo revertir si algo sale mal:
- Migración reversible: [sí/no, descripción]
- Feature flag: [sí/no, cómo se toggle]
- Pasos de rollback: [lista concreta]
- Datos afectados: [qué se borra/modifica, cómo recuperar]

## Success Criteria

[Cómo medimos que esto funcionó:
- Métrica observable 1: [valor esperado]
- Métrica observable 2: [valor esperado]
- Comportamiento esperado: [descripción]
- Test que lo verifica: [path al test]
]

## Affected Areas

[Lista de áreas impactadas:
- `src/auth/`: nuevo módulo de login
- `src/api/users.ts`: cambio en endpoint existente
- `database/migrations/`: nueva migración X
- `docs/api/`: nueva documentación
- `.opencode/context/decisiones/`: nueva decisión X
]

## Dependencies

- Bloqueado por: [otros changes que deben completarse antes]
- Bloquea a: [changes que dependen de este]
- Dependencias externas: [librerías, servicios, integraciones nuevas]

## Stakeholders

- Requester: [quién lo pidió]
- Reviewers: [Pol, Sol, Teo, Jhon, Luz según aplique]
- Approver: [usuario final]
