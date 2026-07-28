# Tests del installer

Tests que validan la instalación y comportamiento de Skalling.

## Pendiente (Fase 6 del plan)

- `tests/setup.test.sh` — ejecuta install-global.sh con HOME mockeada, valida estructura, parsea frontmatter, ejecuta bootstrap, corre doctor.
- `tests/agent-frontmatter.test.sh` — valida que cada agente tenga `mode`, `permission`, `description` correctos.
- `tests/constitution.test.sh` — valida que constitución tenga todas las reglas R1-R13.
- `tests/okf-template.test.sh` — valida que cada template OKF tenga frontmatter válido.
