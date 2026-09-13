# Modelo de seguridad de Skalling

Skalling usa controles superpuestos. Cada control resuelve un riesgo distinto;
ninguno debe presentarse como una frontera de seguridad que no puede ser.

## 1. Disciplina local

Los contratos de agentes, receipts y hooks Git dan feedback rápido y evitan
errores accidentales. Un usuario que controla el checkout puede omitir un hook,
usar `--no-verify` o modificar esos artefactos. Por eso esta capa no autoriza
por sí sola un merge, una publicación ni una operación destructiva.

## 2. Control de ejecución

Los permisos de OpenCode, el sandbox y los helpers protegidos limitan lo que un
agente puede hacer durante una sesión. Las acciones locales, reversibles y
dentro del rol pueden avanzar sin interrupción. Datos persistidos, secretos,
instalaciones, publicación y acciones irreversibles requieren una frontera más
estricta. `teamdb_destructive` exige una operación exacta, respaldo y
autorización explícita; no protege otras bases ni programas externos.

## 3. Control autoritativo

La integración confiable ocurre fuera del checkout: CI, ramas protegidas,
revisiones requeridas, permisos del proveedor y credenciales limitadas. La CI
debe volver a ejecutar las verificaciones relevantes y no confiar solamente en
un receipt o una TeamDB local mutable.

### Configuración obligatoria fuera del repositorio

El administrador del proveedor Git debe proteger `main`: exigir que termine el
workflow **Tests**, exigir revisión de pull request según la política del equipo,
impedir force-push y borrado de rama, y limitar quién puede modificar reglas y
secretos. Este repositorio declara y ejecuta las pruebas, pero no puede activar
esas reglas desde un checkout; hasta que estén configuradas, no se debe afirmar
que existe una frontera de integración protegida.

## Autorizaciones útiles para el usuario

El agente pide autorización por una consecuencia, no por cada comando interno.
Antes de hacerlo explica: acción, motivo, alcance, riesgo, recuperación y
recomendación. Una autorización cubre una decisión y su alcance declarado; no
autoriza publicación, nuevos destinos ni pérdida de datos adicional.

## Independencia de verificación

Teo implementa; Jhon forma un oráculo independiente y aprueba. TeamDB rechaza
que el actor que entregó una implementación sea quien la aprueba. Esta es una
defensa de proceso: la identidad fuerte del agente y la protección contra un
usuario que manipula el checkout corresponden al runtime y a la plataforma de
integración.
