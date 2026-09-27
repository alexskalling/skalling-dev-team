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

### Política de permisos: lista blanca

Todo comando bash que no esté explícitamente permitido pide autorización
(`"*": "ask"` en todos los roles, generado desde `data/permission-policy.json`).
Se permiten sin preguntar la lectura del proyecto, los tests y linters del
proyecto y los helpers de TeamDB de cada rol. Instalar paquetes, publicar,
reescribir historia, borrar, tocar infraestructura (`gh`, `aws`, `kubectl`,
`terraform`, `docker`...) o nombrar rutas de credenciales pide permiso.

Límites que siguen existiendo y hay que conocer:

- `npm test`, `npm run build` y equivalentes ejecutan lo que diga el
  `package.json`, que un rol con edición puede modificar. La ejecución de
  código del proyecto es inherente a implementar y probar: el aislamiento
  real es el del sistema operativo (contenedor, VM, usuario sin
  credenciales de producción).
- `webfetch` sigue permitido a los roles técnicos para leer documentación.
  Una página puede contener instrucciones maliciosas (inyección de prompt);
  la lista blanca impide que se conviertan en comandos o lecturas de
  credenciales sin que el usuario lo vea, pero no impide que el agente
  incluya contenido del proyecto en una URL. Para código confidencial,
  poner `webfetch: ask` en `data/permission-policy.json`.

### Confianza en el `.opencode/` de cada proyecto

OpenCode carga los agentes, plugins y comandos de `.opencode/` del proyecto
que se abre, y los hooks de Git que instala `setup.sh` ejecutan código de
`.opencode/hooks/` y `.opencode/scripts/` en cada `commit`, `pull` y `push`.
Quien puede escribir en la rama principal de un proyecto puede, por lo tanto,
ejecutar código en la máquina de cada integrante. En cada repositorio que use
Skalling en equipo:

- proteger la rama principal (sin push directo, revisión obligatoria);
- exigir revisión de alguien responsable para `.opencode/**`,
  `db/teamdb/**`, `.gitattributes` y `.gitignore` (por ejemplo con
  `CODEOWNERS`);
- no ejecutar Skalling en repositorios de terceros sin revisar antes su
  `.opencode/`.

### Actualizaciones

`update.sh` instala solo releases publicados (tags `vX.Y.Z`), nunca el
último push a `main`. Con `SKALLING_REQUIRE_SIGNED_TAGS=1` exige que el tag
esté firmado. Publicar un release es el punto de control: debe hacerse desde
un commit con CI en verde.

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
