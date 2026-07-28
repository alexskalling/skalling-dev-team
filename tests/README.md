# Tests del instalador

Todos los tests están en un solo archivo: `setup.test.sh` (150+ pruebas).

## Qué prueban

- Que los 8 agentes tengan frontmatter correcto (`mode`, `permission`, etc.)
- Que la constitución tenga las 16 reglas (R1-R16)
- Que los 7 comandos estén presentes
- Que los scripts tengan sintaxis bash válida
- Que el bootstrap funcione de principio a fin
- Que la detección de lenguajes funcione en diferentes stacks
- Que el instalador sea portable (macOS, Linux, WSL, Git Bash)
- Regresión Tier 1 (fixes críticos)

## Cómo correrlos

```bash
bash tests/setup.test.sh
```
