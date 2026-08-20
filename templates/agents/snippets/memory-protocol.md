# 🧠 Memory Protocol (snippet canónico)

> **Este snippet es single source. Las copias en cada agente están sincronizadas por convención. Si editás este archivo, propagá a las 8 copias** (`agents-base/{Alex,Pol,Jes,Sol,Teo,Jhon,Luz,Pau}.md`).

---

## Cuándo guardar

Evaluá **antes de cerrar tu handoff al siguiente agente** (o tu propio ciclo si sos terminal). Guardá si la información cumple alguno de estos momentos clave:

- **Decisión arquitectónica forzada** (ej: "elegimos X sobre Y porque Z", tradeoff que no se ve en el código).
- **Tradeoff no obvio** (decisión donde el código "correcto" en abstracto era peor para este proyecto).
- **Contradicción detectada** (lo que decidiste choca con un concept doc existente — no proceder en silencio).
- **Gotcha o workaround** (algo que rompería a quien venga sin contexto).
- **Cambio de estado de un feature** (de "en curso" a "bloqueado", o de "bloqueado" a "resuelto").
- **Fin de feature** (síntesis de lo aprendido al cerrar la tarea).

**NO guardes trivialidades**: typos, renames, configs de una sola línea, hechos genéricos que se ven en el código, o decisiones que se explican solas en el diff.

---

## Dónde guardar

DB tables (fuente de verdad, NO archivos):

| Tabla | Uso |
|---|---|
| `concepts` | Cosas concretas del proyecto (stack, módulo, API, tabla) |
| `decisions` | ADRs (decisiones arquitectónicas con por qué) |
| `preferences` | Convenciones del equipo / elección de herramientas |
| `known_problems` | Workarounds activos |
| `work_in_progress` | Features/tareas activas |

**Los `.md` en `.opencode/context/` son EXPORTS derivados, nunca la fuente.** Los agentes INSERTAN en las tablas. Solo Pau consolida al cerrar.

---

## Cómo marcar contradicciones

Si detectás que lo que hiciste/decidiste **contradice un concept doc existente**:

1. **En tu handoff al siguiente agente**, agregá un campo explícito:
   ```json
   "contradicciones_detectadas": [
     "path/al/concept/doc.md — razón breve de la contradicción"
   ]
   ```
2. **En el concept doc contradicho**, agregá una sección `## ⚠️ Contradice` con:
   - Referencia al nuevo doc/handoff que lo contradice.
   - Razón de la contradicción.
   - Estado: pendiente / resuelto.
3. **NO proceder como si nada.** Notificar a Alex para escalar al usuario — la contradicción puede ser intencional o un error, pero la decisión la toma el humano, no vos.

---

## Qué NO guardar (R10 — seguridad e higiene)

- **Secrets, credenciales, API keys, tokens, contraseñas** — ni siquiera en examples. Si un ejemplo necesita una key, usá un placeholder obvio tipo `YOUR_API_KEY_HERE`.
- **Información personal identificable** (PII) de usuarios, clientes o del equipo.
- **Datos privados de negocio** que no ayudan a entender el proyecto en el futuro (revenue de clientes, márgenes, etc.).
- **Código que se ve en el repo** — el código es la verdad; la memoria es sobre **decisiones y contexto detrás** del código, no sobre el código mismo.
- **Hechos genéricos que están en la documentación oficial** (no es tu trabajo duplicar la doc de una librería).

---

## Recordatorio R12

El bundle OKF (`.opencode/context/`) es **local al proyecto**. No se replica ni sincroniza con la nube automáticamente. El backup es responsabilidad del usuario vía `git`. Si commiteás cambios en el bundle, van al repo; si no los commiteás, se pierden al cambiar de máquina.

---

**Sincronización**: Si modificás este snippet, las 8 copias en los agentes (`agents-base/*.md`) deben actualizarse en el mismo PR. El comment block `<!-- SINCRONIZADO CON: templates/agents/snippets/memory-protocol.md. ... -->` al inicio de cada copia es la disciplina que permite detectar desincronizaciones.
