# Pruebas de Skalling

La validación está dividida por comportamiento: `setup.test.sh` comprueba el
instalador y `teamdb-hardening-suite.sh` ejecuta las suites de TeamDB,
seguridad, agentes, dashboard, portabilidad y contratos de publicación.

## Qué prueban

- Que los 8 agentes tengan frontmatter correcto (`mode`, `permission`, etc.)
- Que la constitución tenga las 17 reglas (R1-R17)
- Que los 13 comandos estén presentes
- Que los scripts tengan sintaxis bash válida
- Que el bootstrap funcione de principio a fin
- Que la detección de lenguajes funcione en diferentes stacks
- Que el instalador sea portable (macOS, Linux, WSL, Git Bash)
- Regresión Tier 1 (fixes críticos)

## Cómo correrlos

```bash
bash tests/setup.test.sh
bash tests/teamdb-hardening-suite.sh
```
