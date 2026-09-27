# Política de seguridad

## Versiones con soporte

Solo el último release publicado (tag `vX.Y.Z`) recibe correcciones de
seguridad. `main` puede contener trabajo sin publicar: no instalarlo en
equipos de trabajo (`scripts/update.sh` usa releases por defecto).

## Reportar una vulnerabilidad

No abrir un issue público. Usar el reporte privado de GitHub:
**Security → Report a vulnerability** en este repositorio. Incluir versión,
sistema operativo, versión de OpenCode, pasos para reproducir e impacto.

Especialmente relevante:

- comandos que un agente ejecuta sin pedir permiso y no deberían
  (ver la política en `data/permission-policy.json`);
- formas de saltear el gate de Git o de fabricar un receipt;
- fuga de datos de la memoria (`team.db`, `db/teamdb/team.dump.sql`) o de
  credenciales;
- ejecución de código a partir de contenido de un dump, una página web o un
  archivo del proyecto.

## Alcance

El modelo de amenazas y sus límites están en
[docs/security-model.md](docs/security-model.md). Los hooks y receipts son
controles de calidad locales, no una frontera frente a quien controla el
checkout.
