<!-- SINCRONIZADO CON: single source para los 8 agentes. -->
# 🧠 Memory Protocol

## Cuándo guardar

Solo ante una decisión arquitectónica, preferencia confirmada, contradicción, workaround, problema conocido o aprendizaje no evidente en el código. Los agentes proponen candidatos; Pau consolida.

## Dónde guardar

TeamDB es la fuente. Pau usa `teamdb-memory.sh` para `concepts`, `decisions`, `preferences` y `known_problems`. `.opencode/context/` contiene únicamente exports derivados.

## Cómo marcar contradicciones

Incluí en el handoff la tabla/slug, la regla anterior, la evidencia nueva y la decisión humana requerida. Nunca sobrescribas historia silenciosamente; usá relaciones `contradicts` o `supersedes`.

## Qué NO guardar

No guardes secretos, PII, conversaciones, código reproducible desde el repo, hechos genéricos, resultados transitorios ni resúmenes rutinarios. Si no hay conocimiento durable: `MEMORY_CHECK: NO_CHANGE`.
