# Changelog

Todos los cambios notables a Skalling se documentan acá. El formato sigue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.11.16] — en preparación

Agujeros vistos en una sesión real con v0.11.15 instalada (ucadigital,
OpenCode 2.0.18). Lo que funcionó: Alex tuvo que clasificar antes de
delegar a Teo, y Teo no pudo sellar un receipt como jhon ("identidad
declarada 'jhon' no coincide con el agente real 'teo'"). Lo que no: el
commit se hizo con `git commit --no-verify`, saltando el gate.

### Security
- **Nadie salta los hooks de git**: `--no-verify`, `git commit -n`,
  `core.hooksPath` y `HUSKY=0` se bloquean (mirando fuera de las comillas:
  un mensaje de commit que los menciona pasa). Alex tampoco los propone ni
  se los sugiere al usuario; si el gate bloquea, falta la verificación de
  Jhon o Luz (para un commit ya hecho: `skalling-review.sh --diff`).
- **TEAMDB_CLAIM_\*** (hash, exit code y resumen que sella un receipt) no
  los puede fijar un agente: se fijó a mano un hash para "aprobar" un
  candidato distinto al staged.
- **Cada rol lo hace su agente**: si la descripción de un subagente nombra
  a un rol ("Jhon sella receipt") y el `agent` es otro (Teo), se bloquea.
- **Motor de borrado de TeamDB**: solo corre en su forma de terminal
  (`python3 …/teamdb-destructive.py preview|apply …`) con el SQL a la
  vista; mandarle JSON por stdin o por pipe esquivaba la aprobación y se
  bloquea. `apply` siempre pregunta en la política.

### Fixed
- `cd <dir>` seguido de un git sensible con salto de línea o `;` (la forma
  en que Alex escribe los comandos) se bloqueaba como "encadenado": Alex
  concluyó que "el guard bloquea todo push" y propuso `--no-verify`. Ahora
  pasa y el permiso pregunta; el mensaje del guard aclara que los
  argumentos normales están bien y sugiere el parámetro `workdir`.

### Added (OpenCode v2)
- `teamdb_destructive` en v2: la herramienta hace la vista previa y
  devuelve el comando exacto de aplicar; el permiso nativo de la terminal
  lo pregunta mostrando base, SQL y parámetros, y un hook de permisos lo
  fuerza a preguntar aunque exista un "permitir siempre". El motor sigue
  respaldando antes y rechazando si la base cambió.
- `skalling_workflow` en v2: un `check` corre si la política compilada del
  agente ya permite ese comando (p. ej. `npm test` para Jhon); si pediría
  aprobación se rechaza, porque un plugin v2 no puede preguntar.

### Límite conocido
- `/skalling-goal` (modo autónomo) sigue solo en v1: en v2 hay que
  reescribirlo sobre sus APIs nuevas de comandos, eventos y sesiones, y
  no se publica sin verificarlo con sesiones reales (un error ahí puede
  dejar al agente enviándose mensajes en bucle). En v2 no se registra y
  no concede nada.

## [0.11.15] — en preparación

El flujo ya no depende de que Alex quiera respetarlo. Motivo: una sesión
real (proyecto ucadigital, OpenCode 2.0.18) donde Alex, con el editor
bloqueado, buscó otra vía y cambió 3 archivos por la terminal (`sed -i`,
`python3 <<PY open(path, 'w')`), sin clasificar, sin Teo y sin Jhon, y
después lo justificó con un `AGENTS.md` viejo del proyecto.

### Fixed
- **Los plugins de Skalling no cargaban en OpenCode v2.** La v2 exige
  `export default { id, setup }` y los rechazaba ("Plugin must export a
  default definition…"); además su terminal se llama `shell`, no `bash`, y
  el guard solo miraba `bash`. En v2 no había guard, ni identidad de
  runtime, ni bloqueos. Ahora cada plugin exporta un único
  `default { id, server, setup }`: la v1 usa `server` y la v2 usa `setup`.
  El guard corre en las dos (v1: `tool.execute.before` + `shell.env`; v2:
  `ctx.tool.hook('execute.before'|'execute.after')` +
  `ctx.shell.hook('create.before')`).
- En v2 un bloqueo reemplaza el comando por un `echo` con el motivo, porque
  un error lanzado desde un hook de la v2 no se convierte en un rechazo
  limpio.
- La identidad del runtime ya no se inyecta reescribiendo el comando (eso
  hacía que dejara de coincidir con su permiso y preguntara de más): va en
  el entorno del proceso (v1: `shell.env`; v2: `create.before`).

### Security
- **Alex no escribe archivos por ninguna vía de la terminal** (ni los roles
  sin edición): `sed -i`, `perl -i`, `cp/mv/touch/tee/patch/git apply`,
  redirecciones y código inline (`python -c`, `node -e`) que escribe
  archivos. El mensaje le dice qué hacer: delegar a Teo con la herramienta
  de subagente. Su prompt lo refuerza: un bloqueo es la señal de que el
  trabajo es de otro, no una herramienta que falte; nunca "hacer de Teo".
- **Sin clasificación no se delega implementación**: Alex no puede mandar
  trabajo a Teo (`task`/`subagent`) si en esa sesión no corrió
  `skalling-route.sh classify` con un `request_id`. Delegar investigación
  (Jes) no lo requiere.
- **Commit solo con aprobación de un verificador**: `git-gate.py` exige un
  receipt de Jhon o Luz sobre el candidato exacto staged; uno de Alex o de
  Teo ya no habilita el commit. Jhon sella también en el carril directo, y
  Alex le pide ese sello antes de commitear.

### Added
- El doctor avisa si el proyecto tiene un `AGENTS.md` de una versión vieja
  de Skalling con el "fast-track, ejecuta bajo tu criterio" que contradice
  el flujo actual (`tests/doctor-stale-agents-md.test.sh`).

### Límite conocido
- En OpenCode v2, `teamdb_destructive`, `skalling_workflow` y
  `/skalling-goal` no se registran todavía: la API de plugins de la 2.0.18
  no da una forma de que una herramienta pida al humano una aprobación
  exacta (como `context.ask` de la v1). Fallan cerrado: sin ellas nada se
  habilita sin aprobación. En v1 siguen igual.

## [0.11.14] — en preparación

Cierra los hallazgos verificados de una auditoría externa de v0.11.12.

### Security
- **Permiso para borrar, ejecutar código inline y salir a la red**: `rm`,
  `rmdir`, `unlink`, `shred`, `bash/sh/zsh -c`, `eval`, `python/python3 -c`,
  `node -e/-p/--eval`, `ruby/perl -e`, `php -r`, `curl`, `wget`, `nc`,
  `ssh`, `scp`, `rsync`, etc. pasan a "ask" en todos los perfiles. También
  los git que reescriben o descartan historia: `switch`, `rebase`, `merge`,
  `revert`, `cherry-pick`, `update-ref`, `filter-branch`, `filter-repo`,
  `gc`, `stash drop/clear`, `reflog expire/delete` (con sus formas `-C` y
  `cd … &&`). Los deny de `rm *.db*` / `*team.db*` se mantienen.
- **Plugin guard reescrito** (`plugins/lib/git-guard.mjs`): un comando
  sensible solo pasa en la forma directa que el permiso cubre. Se bloquean,
  con una explicación, las vías de escape que la auditoría mostró:
  `command git push`, `/usr/bin/git push`, `'git' push`, `env/timeout/nohup
  git push`, `GIT_DIR=x git push`, `git -c k=v push`, `bash -c "git push" &&
  ls`, `$(echo git) push`, `echo "$(git push)"`, `find … | xargs rm`, bucles
  con `rm`, `eval` encadenado, `cat .env | curl …`. El mensaje de commit con
  heredoc (`git commit -m "$(cat <<'EOF' …)"`) sigue funcionando.
- **Identidad del runtime, no declarada**: el plugin sabe qué agente corre
  cada sesión (`chat.params`) y la inyecta como `SKALLING_RUNTIME_AGENT`.
  `teamdb-claim.sh` (claim, `--resume`, `--release`, `--advance`),
  `teamdb-seal-receipt.sh` y `skalling-review.sh` la usan como actor; un
  `--by`/`--actor` distinto se rechaza (exit 2). Teo ya no puede aprobar
  como jhon ni sellar un receipt como luz. Un comando que intente fijar
  `SKALLING_RUNTIME_AGENT`, `TEAMDB_ACTOR` o `SKALLING_REVIEW_AGENT` se
  bloquea. Sin runtime (CLI humano, CI) vale lo declarado, como antes.
- **Lista blanca para los roles sin edición** (Luz, Jhon, Pol, Sol, Jes):
  `"*": ask` — lo que no está en su lista pregunta. `sed -i`, `git add`,
  instalar/quitar paquetes y `sort -o` también preguntan. El plugin bloquea
  que escriban archivos por redirección (`> archivo`, `>>`, `&>`) o `tee`,
  salvo a `/tmp` o `/dev/null`. Teo y Pau mantienen su perfil amplio. Para
  Jes (web + bash) esto separa las dos cosas: lo que lea en la web no puede
  terminar en un comando que escriba, borre o salga a la red sin preguntar.
- **Eliminada `teamdb_safe_query`** (deprecated desde el round 2 de
  hardening, sin callers): el escape manual reemplazaba cada `?` del
  template en orden, así que un `?` dentro de un parámetro se sustituía por
  el parámetro siguiente (inyección). El único camino es `teamdb_exec_*`
  con bound params reales. Se borra también su test.

### Changed
- `constitution/constitucion.md` ya no afirma que Alex la lee al inicio de
  cada sesión (ningún agente la carga): se declara referencia para
  personas, y explica dónde vive lo que sí se hace cumplir.
- Sol puede correr `teamdb-export-md.sh` sin preguntar (sus instrucciones
  lo usan y no estaba en su lista).

### Tests
- `tests/git-guard-plugin.test.mjs`: vías de escape, formas directas,
  identidad, inyección, hooks y escrituras de roles de solo lectura.
- `tests/teamdb-runtime-identity.test.sh` (nuevo, en la suite).

### Límite conocido
- Un agente con permiso de edición (Teo) puede escribir un script y
  correrlo; la verificación que no se puede falsificar vive en CI.

## [0.11.13] — en preparación

A pedido explícito del usuario: trabaja en proyectos externos (de clientes,
no de su propia empresa) y le preocupaba que la memoria de Skalling — o
peor, las reglas de los agentes — terminaran commiteadas en un repositorio
que no es suyo.

### Added
- `/skalling-privacy interno|externo` (+ `scripts/skalling-privacy.sh`,
  acepta también `internal`/`external`): marca un proyecto como interno
  (memoria compartida por git, comportamiento de siempre) o externo. En modo
  externo, agrega `.opencode/` y `db/teamdb/` a `.gitignore` (bloque
  marcado, idempotente, no toca el resto del archivo) — de ahí en más, la
  memoria de Skalling nunca se commitea ni se pushea. Si algo ya estaba
  commiteado ANTES de marcar el proyecto como externo, avisa explícitamente
  con la lista de archivos — el `.gitignore` protege hacia adelante, no
  borra el historial de git, eso queda para una decisión aparte del
  usuario. Volver a `interno` saca solo el bloque que el propio comando
  agregó, sin tocar el resto del `.gitignore`.
- `/skalling-init` pregunta interno/externo la primera vez que inicializa un
  proyecto de verdad (`privacy_mode` ausente en `schema_meta`); si ya está
  configurado, no vuelve a preguntar.

### Investigado (sin cambios de código, aclara una preocupación real)
- Confirmado leyendo el código: en el flujo normal (`/skalling-init` →
  `bootstrap-context.sh`), los archivos de los agentes (Alex, Sol, etc. con
  todas sus reglas) **nunca se escriben dentro de un proyecto** — viven
  solo en `~/.config/opencode/agents/`, en la máquina del usuario. Existe un
  modo alternativo (`setup.sh`, "team-sharing") que si se corre a mano SÍ
  copia los 8 agentes completos a `<proyecto>/.opencode/agents/` y puede
  crear un `AGENTS.md` en la raíz anunciando el uso de Skalling (opt-in,
  default "no") — pero ningún comando `/skalling-*` invoca ese modo, y como
  los archivos que copia caen bajo `.opencode/`, el mismo `.gitignore` de
  modo externo ya los cubre.

## [0.11.12] — en preparación

A partir de comparar Skalling con otro framework de agentes (rsc-harness),
cuyo principio de "evidencia antes que anticipación" esta sesión no venía
aplicando: cada fix de esta noche agregó código sin chequear si algo
anterior había quedado sin conectar.

### Added
- `scripts/skalling-dead-code-check.sh` (+ `check_dead_code` en
  `setup-team-doctor.sh`): detecta scripts/plugins instalables sin ningún
  caller real (agente, comando, skill u otro script) — solo aparecer en
  `tests/`, en `install-global.sh` (copiado) o en `.bundle-manifest`
  (listado) NO cuenta como uso real. Convierte en chequeo repetible lo que
  hasta ahora se encontraba por auditoría manual casual (pasó dos veces en
  esta misma sesión: `skalling-context-cache.sh` instalado y nunca llamado;
  `teamdb-task-groups.sh` construido sin wire hasta que un humano lo notó).

### Fixed
- Corriendo el checker contra el propio repo, encontró 5 huérfanos reales:
  - `teamdb-context-cache.sh` — reemplazada por `teamdb-context.sh` (sin
    cache), que es la que de verdad se usa. **Borrada.**
  - `teamdb-graph-refresh.sh` — sobrante de cuando `/skalling-graph-refresh`
    se consolidó en `/skalling-memory` (que llama `teamdb-link.sh` directo).
    **Borrada.**
  - `teamdb-with-timeout.sh` — el manejo de timeout real terminó resuelto
    inline en cada función (`teamdb_lock` ya tiene su propio timeout).
    **Borrada.**
  - `teamdb-ingest-change.sh` — herramienta de migración manual legítima
    (misma categoría que `migrate-plans-md-to-db.sh`, que ya era excepción).
    **Agregada al allowlist**, no borrada.
  - `teamdb-attempt.sh` — infraestructura real de v0.8.3 (presupuesto de
    reintentos por change, con manejo de race conditions) que nunca se
    conectó a ningún agente. **Reconectada**: Teo ahora llama
    `acquire`/`settle` en su flujo medium/high, reemplazando la regla de
    prosa "máximo tres correcciones" (dependía de que Teo se acordara) por
    un tope forzado por código.

## [0.11.11] — en preparación

Bug real reportado en vivo por el usuario, en un proyecto suyo
(`actas3.0.0`): el bootstrap fallaba con `duplicate column name` al aplicar
la migration `009_plan_contract`, en un loop imposible de resolver solo
reintentando.

### Fixed
- `teamdb-init.sh`: diagnosticado leyendo el `team.db` real del proyecto —
  la migration `009_plan_contract` ya había corrido y comiteado sus cambios
  de verdad en algún momento anterior (columnas presentes, `schema_meta.
  version` en el valor exacto que esa migration deja), pero la escritura
  posterior que la registra en `applied_migrations` nunca se guardó. Cada
  bootstrap futuro la reintentaba contra un schema que ya tenía esos
  cambios, fallando siempre. La causa de código: `_run_sql()` no chequeaba
  si esa escritura de registro fallaba — la ignoraba en silencio y reportaba
  éxito igual. Una migration ya comiteada no se puede deshacer desde el
  script; ahora, si el registro falla, el bootstrap falla fuerte (en los dos
  caminos: baseline de un proyecto nuevo, y aplicación real sobre un
  proyecto existente), para que quede evidencia clara en vez de un estado
  corrompido en silencio.

## [0.11.10] — en preparación

A pedido explícito del usuario, atiende el ítem que había quedado señalado
como pendiente en la autocrítica original: "los lenses de revisión siguen
siendo regex, no análisis estático real".

### Added
- `skalling-review.sh --lens sast` (incluido en `--lens all`): corre
  `semgrep` de verdad (registry `p/owasp-top-ten` + `p/security-audit`,
  override con `SKALLING_SEMGREP_CONFIG`) sobre el contenido STAGED de los
  archivos tocados con extensión soportada (`.py .js .jsx .mjs .ts .tsx .go
  .java .rb .php`). La diferencia real con "risk" (el lens regex existente):
  sigue el dato entre variables intermedias antes de llegar al sink
  peligroso, no solo mira la línea donde termina. Probado en vivo: un caso
  donde el dato pasa por dos variables (`dato -> parte -> query ->
  cursor.execute(query)`) — invisible para cualquier regex de una sola línea
  — semgrep sí lo marca como BLOCKER, y una query parametrizada equivalente
  no genera falso positivo.
- Degradación honesta si `semgrep` no está instalado o no puede correr (sin
  red la primera vez que hace falta el ruleset del registry, timeout): NO
  bloquea — no se puede exigir esa herramienta en toda máquina para
  siempre — pero deja un `INFO` explícito en el receipt sellado
  (`"sast":{"ran":1,"available":0,...}`), nunca indistinguible de una
  corrida que sí tuvo esa capa. Mismo principio que la degradación de
  `skalling-coverage.sh` cuando no hay comando de test configurado.
- El escape hatch `# lens:ok: motivo` (ya usado por los otros 4 lenses)
  también aplica acá — se lee la línea real del archivo (no el campo
  `extra.lines` de semgrep, que viene redactado para ciertos rulesets sin
  cuenta) en cualquier punto del rango que reporta el finding, porque una
  relación de taint puede cruzar varias líneas entre la fuente y el sink.

### Fixed (encontrado implementando esto)
- Un heredoc de Python anidado dentro de un `process substitution
  < <(...)` rompía en bash 3.2 (el bash default de macOS, el que este
  proyecto explícitamente soporta) con "ambiguous redirect" — se resolvió
  escribiendo el script a un archivo temporal aparte antes de invocarlo.

## [0.11.9] — en preparación

Un agente sin memoria de la sesión que escribió v0.11.6 hizo una revisión
adversarial de esos 3 fixes de seguridad, a pedido explícito del usuario
(preocupación válida: el autor revisando su propio código no es
independiente). Encontró 6 bugs confirmados y 3 puntos plausibles que la
sesión original no había visto. Se arreglan acá.

### Fixed
- `skalling-verify.sh`: el parseo de `project.yaml` exigía que
  `available:` estuviera pegado justo antes de `command:`; reordenar esas
  dos claves (o poner un comentario en medio) hacía que cayera en silencio
  a "sin configurar", volviendo a confiar en el exit code del caller —
  exactamente lo que v0.11.6 decía haber cerrado. Ahora aísla el bloque de
  `unit:` y busca ambas claves sin asumir orden ni adyacencia. También
  ignoraba `available: false` si quedaba un `command:` viejo colgado; ahora
  lo respeta.
- `teamdb-seal-receipt.sh`: TOCTOU real — el test corría sobre el working
  tree pero el hash sellado era el del índice (staged). Confirmado en vivo:
  stagear código malo, sobreescribir el archivo con código bueno sin volver
  a `git add`, sellar — quedaba un receipt "exitoso" para código que nunca
  se probó. Ahora exige que el working tree coincida con el índice antes de
  correr la verificación real de jhon.
- `git-gate.py` + `teamdb_project_path` (`lib-teamdb.sh`): el fail-closed de
  v0.11.6 resolvía la raíz del proyecto con `--show-toplevel`, que en un
  `git worktree` da la raíz del WORKTREE, no la del repo principal. Como
  `team.db` está gitignored y un worktree nuevo nunca lo trae, el
  fail-closed bloqueaba literalmente TODO commit en TODO worktree — la
  contradicción exacta con el propio commit de paralelización de esta
  sesión. Ahora resuelven vía `--git-common-dir` (compartido entre el repo
  principal y todos sus worktrees).
- `permission-policy.json`: `git branch -d/-D` y `git worktree
  remove/prune` (agregados en v0.11.6) se quedaron sin las variantes
  `git -C */cd &&` que sí se les dio a los otros 6 comandos sensibles en la
  misma versión — inconsistencia detectada por la revisión.
- `teamdb-seal-receipt.sh`: mantenía el lock de TeamDB tomado durante toda
  la corrida del test real del proyecto, que puede tardar bastante más que
  el timeout del lock (10s) — bloqueando de hecho a los otros agentes que
  quisieran escribir en TeamDB mientras tanto. Ahora lo libera antes de
  correr la verificación y lo vuelve a tomar recién para escribir el
  receipt. También trunca `output_summary` a 4000 caracteres (no tiene
  límite en la columna).
- `tests/mirror-parity.test.sh`: solo recorría fuente → espejo; un archivo
  huérfano en `.opencode/agents/` o `.opencode/hooks/` (borrado de la
  fuente pero no del espejo) no se detectaba. Ahora también busca
  huérfanos.

### Added
- `plugins/skalling-git-guard.js` (+ `plugins/lib/git-guard.mjs`): cierra
  un hueco que `permission-policy.json` por sí solo NO puede cerrar — el
  matcher de OpenCode compara el comando bash completo contra cada glob, así
  que un `"allow"` amplio como `"git add *"` matchea literalmente
  `"git add . && git push"` (el `*` final absorbe el `&& git push` pegado
  atrás). Ninguna de las variantes endurecidas en v0.11.6 usa ese prefijo,
  así que ese fix no lo cerraba. El plugin intercepta `tool.execute.before`
  y bloquea cualquier comando bash que encadene (`&&`/`;`/`|`) uno de los
  git sensibles detrás de otro prefijo — forzando a que se corra como su
  propio comando, donde el permiso `"ask"` ya configurado sí aplica.

### Sin resolver, a propósito
- La revisión también señaló que sellar un receipt de jhon ahora ejecuta
  código controlado por el propio proyecto (`testing.unit.command`). No es
  una clase de vulnerabilidad nueva — es el trabajo real de un "test
  verifier", y `skalling-coverage.sh` ya ejecutaba comandos de proyecto de
  la misma forma antes de esta sesión — pero antes de v0.11.6, sellar un
  receipt nunca ejecutaba nada. Documentado, no mitigado.

## [0.11.8] — en preparación

A pedido explícito del usuario: agrega el test de paridad de espejos que
faltaba de la autocrítica.

### Added
- `tests/mirror-parity.test.sh` vigila dos mecanismos de "espejo" de
  archivos que no tenían ningún test: `agents-base/*.md` →
  `.opencode/agents/*.md` (vía `render-agent.sh`) y `scripts/hooks/*` →
  `.opencode/hooks/*` (copia cruda, sin script que la aplique). El tercer
  mecanismo (`scripts/.bundle-manifest` → `.opencode/scripts/`) ya tenía
  cobertura en `tests/scripts-parity.test.sh` y no se duplica.

### Fixed
- **`.opencode/agents/Alex.md` tenía `hidden: true` colado por accidente**
  en el commit `1ea5523` (cuyo mensaje no lo menciona en absoluto) — nunca
  estuvo en `agents-base/Alex.md`, la fuente. `hidden: true` es un patrón
  real e intencional para agentes internos delegados (Jhon, Pau, Luz), pero
  nunca debería aplicar a Alex, el orquestador de cara al usuario y punto de
  entrada de Skalling; en esta copia local del repo, Alex podía estar
  invisible en el selector de agentes sin que nadie lo hubiera decidido.
  Encontrado por el propio `mirror-parity.test.sh` recién escrito.

## [0.11.7] — en preparación

A pedido explícito del usuario: cierra la brecha "construimos el detector,
nadie lo usa" señalada en la autocrítica de la versión anterior.

### Added
- **`teamdb-plan.sh` corre `teamdb-task-groups.sh` automáticamente al crear
  un plan.** Antes, saber qué tasks eran paralelizables requería que un
  humano se acordara de correr `teamdb-task-groups.sh` a mano después de que
  Sol armara el plan — la herramienta no generaba ningún valor real hasta
  que alguien la usara manualmente. Ahora, si hay tasks sin vínculo entre sí
  (candidatas a un worktree cada una) o tasks bloqueadas por una dependencia
  sin resolver, queda anotado directamente en el `design_md` del plan, con
  un `plan_history` versionado (`operation='amended'`) para que quede
  auditable. Un plan trivial (una sola task, o todo en una sola cadena
  secuencial) no recibe ninguna nota — no ensucia el plan con contenido sin
  valor. `agents-base/Sol.md` documenta el comportamiento nuevo.

## [0.11.6] — en preparación

Cierra 3 huecos reales de seguridad/calidad, a partir de una autocrítica
pedida explícitamente por el usuario ("si fuera tu decisión, qué le harías a
este agente para que sea más seguro/efectivo/evidente").

### Fixed
- **`git-gate.py` pasa a fail-closed.** Antes, si `team.db` no existía, el
  chequeo de "receipt de revisión aprobada" se saltaba en silencio
  (`if not db or ...: return`) y un commit de código pasaba sin ninguna
  revisión. Ahora, si se commitea código y no hay `team.db`, bloquea con un
  mensaje explícito en vez de dejarlo pasar.
- **`git -C <dir> push` y `cd <dir> && git push` (y los mismos para reset,
  clean, checkout, restore, commit) pasaban por alto el "ask".** La forma
  literal `git push`/`git push *` ya pedía permiso, pero esas dos variantes
  no matcheaban ningún patrón específico y caían al wildcard `"*": "allow"`
  — un hueco real dado que el flujo de worktrees que promueve el propio
  proyecto hace exactamente eso (`cd` a otro directorio, o `git -C
  <worktree>`, y después `git push`). Se agrega también `git branch -d/-D` y
  `git worktree remove/prune` (destructivos, sin cobertura previa).
- **`teamdb-seal-receipt.sh` ya no confía en el exit code que le pase el
  caller cuando el agente es `jhon`.** Jhon es el "test verifier": antes,
  sellar un receipt suyo aceptaba `TEAMDB_CLAIM_EXIT_CODE` (default 0) sin
  correr nada real. Ahora, si el proyecto tiene `testing.unit.command`
  configurado en `project.yaml` (detectado, nunca inventado), se corre de
  verdad vía el nuevo `scripts/skalling-verify.sh` y su exit code real es el
  que queda sellado — un test roto bloquea `in_review->approved` solo, sin
  depender de que alguien se acuerde de correrlo a mano. Sin comando
  configurado, sigue sellando (no se puede bloquear para siempre un proyecto
  sin tests) pero el `output_summary` queda anotado `SIN-CONFIGURAR`, nunca
  indistinguible de una verificación real que pasó.

## [0.11.5] — en preparación

### Added
- `/skalling-models`: asigna un modelo de OpenCode a cada uno de los 8
  agentes de forma independiente (`show` / `set <Agente> <modelo>` /
  `reset [Agente]`), usando el campo `model:` del frontmatter del agente
  instalado. La asignación queda en `model-overrides.json`, en la
  instalación global (no en el repo) — `install-global.sh` la reaplica
  después de cada reinstall, para que no se pierda al regenerar los
  agentes desde `agents-base/`. Reemplaza al viejo `skalling-models.sh`
  retirado, que compartía solo 4 slots genéricos entre los 8 agentes; la
  versión actual de OpenCode sí soporta `model:` independiente por agente.
- `teamdb-task-groups.sh`: agrupa las tasks pendientes de un plan en lotes
  seguros para trabajar en paralelo (un worktree por lote), usando solo
  `task_dependencies` real — cualquier vínculo registrado, no solo
  `blocks`, fuerza secuencia entre dos tasks ya listas para arrancar.

### Fixed
- `tests/teamdb-hardening-suite.sh` corre en paralelo (antes secuencial),
  con `dashboard-survives-group-kill.test.sh` aislado en serie aparte
  porque su aislamiento de process group (`set -m`) es incompatible con
  correr como hijo de `xargs -P`.
- `.git/hooks/pre-commit`/`pre-push` resuelven `git-gate.py` con `git
  rev-parse --show-toplevel` en vez de `$(dirname "${BASH_SOURCE[0]}")`,
  que resolvía al path del symlink en `.git/hooks/` y nunca encontraba el
  script real.
- `external_directory` (permiso separado de `bash`, nunca tocado en
  rondas anteriores) pasa de pedir permiso por defecto fuera del proyecto
  a `allow` con una lista corta de rutas sensibles (`.ssh`, credenciales
  de AWS/GitHub, keychains, `.pem`/`.key`, `secrets/`) — el resto de
  operación fuera del proyecto (temporales, `cat`, etc.) no debería pedir
  permiso.

## [0.11.4] — en preparación

Consolida la primera ronda de uso real end-to-end (proyecto Survan) y una
auditoría completa de los comandos `/skalling-*` y el installer.

### Fixed
- Modelo de permisos: `npm install`, `pnpm add/install/remove`, `yarn
  add/remove` pasan de `ask` a `allow` en los 8 agentes — quedaron
  agregados como "ask" al invertir el default general, repitiendo el mismo
  error que se estaba corrigiendo (instalar dependencias declaradas es tan
  rutinario como correr un test, no está en la categoría de "borrar o
  modificar una base de datos").
- `install-global.sh` generaliza la poda de scripts `skalling-*.{sh,py}`
  fantasma (confirmado en vivo: `skalling-context-cache.sh`, ya borrado del
  repo, seguía instalado tras un reinstall) en vez de parchar caso por caso
  cada vez que se remueve uno.
- `skalling-route.sh classify --record` cierra en el código, como
  `superseded`, cualquier métrica del mismo proyecto que haya quedado
  abierta por una reclasificación en los últimos 30 minutos, en vez de
  depender de que Alex lo recuerde por instrucción en markdown. El bug
  anterior (filas colgadas en `pending`) se había "arreglado" con una
  instrucción, que resultó igual de frágil — y el `outcome` con casing
  inconsistente (`SUCCESS` vs `success`) que `summary` comparaba
  literal también se corrige (compara con `LOWER()`).
- `dashboard-server.py` sobrevive a que se mate el process group de quien
  lo lanza: llama `os.setsid()` antes de servir, porque `nohup` (usado por
  `teamdb-dashboard.sh`) solo ignora SIGHUP, no saca al proceso del process
  group de quien lo lanzó. Bug real reportado en uso: "corro
  `/skalling-dashboard` y se cierra solo".
- Auditoría de comandos: elimina código muerto (`skalling-route.sh list` y
  `record` sin caller real, `skalling-context-cache.sh` sin caller y con
  bug de datos falsos si faltan `jq`/`yq`, flag `--project` de
  `skalling-session-start.sh` que nunca cambiaba nada) y desincroniza
  documentado entre `command/README.md` y `skalling-help.md`.

### Added
- `coverage_runs`: historial de corridas de cobertura de tests. Nuevo
  comando `/skalling-coverage` corre el comando de cobertura detectado en
  `project.yaml` (`testing.coverage.command`), reconoce los formatos
  Istanbul (vitest/jest/nyc), `coverage.py` y `go tool cover`, y nunca
  inventa un porcentaje: si el formato no se reconoce, o no hay comando
  configurado, queda constancia de por qué en vez de fabricar un número.
  Ignora artefactos de cobertura viejos que hayan quedado en disco de una
  corrida anterior (compara `mtime` contra el inicio de la corrida actual).
- Dashboard: pestaña "Planes" (activos y pasados, con progreso real —
  el backend ya existía pero nada en el frontend lo llamaba) y panel de
  cobertura de tests en la pestaña "Sistema".

### Migration
- `032_coverage_runs.sql` agrega la tabla y eleva bases existentes a
  schema `0.11.4`.

## [0.11.3] — en preparación

### Fixed
- `teamdb_heal_global` reconstruye `routing_decisions` si el CHECK
  constraint global no incluye `DISCOVERY` (bug crítico bloqueante en
  bases globales existentes; el fix equivalente para bases de proyecto
  ya existía en `sql/migrations/024_version_0_10_3.sql` pero nunca se
  había espejado en el camino de heal global).
- `install-global.sh` borra `teamdb-claim-task.sh` de instalaciones ya
  existentes: quedaba huérfano en disco tras removerlo del repo, porque
  el instalador nunca podaba archivos eliminados.
- `teamdb-read.sh` acepta el proyecto como último argumento posicional,
  igual que el resto de `teamdb-*.sh` (antes exigía `--project` al
  principio y confundía cualquier extra al final con un bind param,
  disparando "Incorrect number of bindings supplied" sin ninguna pista
  útil).
- `workflow_metrics` auto-cierra requests huérfanas (`completed_at IS
  NULL` por más de 2h) antes de insertar una nueva; se perdía sistemá-
  ticamente telemetría por filas nunca cerradas.
- `bootstrap-context.sh` ya no silencia el stderr de `teamdb-init.sh`.

### Changed
- Ciclo de claims unificado en `teamdb-claim.sh` (lease/epoch,
  `input_hash`, transiciones `in_review→approved`/`approved→resolved`
  verificadas por rol); se remueve `teamdb-claim-task.sh` (CAS simple
  sobre `tasks.status/version`, sin expiración de lease, sin callers
  reales).
- Modelo de permisos `bash` de los 8 agentes invertido: de "todo pide
  permiso salvo una lista larga de comandos seguros" a "todo permitido
  salvo una lista corta de operaciones críticas" (`sudo`, instalación de
  paquetes, borrado de archivos de base de datos). El modelo anterior
  era una batalla perdida contra la combinatoria de formas de invocar un
  mismo comando y generaba fricción constante en uso real, incluso para
  lecturas triviales (`cat`, `stat`, `diff`, correr un test).
- Se agregan utilitarios de lectura (`sed`, `which`, `command -v`,
  `test`, `bash -n`, `diff`, `sha256sum`, `mktemp`, etc.) y tolerancia al
  prefijo `cd <ruta> &&` en los `git` de solo lectura ya permitidos.

### CI
- `permission-policy.py` fuerza UTF-8 al leer/escribir (rompía en
  Windows, que usa `cp1252` por default).
- Instala SQLite de Homebrew en `macos-latest`: el del sistema no trae
  FTS5.
- Corrige `teamdb-dag-claims` (shellcheck 0.9.0 en CI vs 0.11.0 local) y
  el smoke test de `readiness degraded`.
- Silencia SC2254 en `skalling-review.sh` (rompía el job "Shell script
  lint").

### Migration
- `031_version_0_11_3.sql` eleva bases existentes a schema `0.11.3`.

## [0.11.2] — en preparación

### Fixed
- `teamdb-link.sh` y `wip-tree.sh` consolidan el escaping SQL en el helper
  compartido `_sql_quote` en vez de reimplementarlo cada uno por su cuenta.
- Fuga de `TMP_DIR` en `teamdb-plan.sh` y `teamdb-ingest-change.sh`: un
  segundo `trap ... EXIT` pisaba en silencio al primero (bash no acumula
  traps), dejando temporales sin limpiar en varios caminos de salida.
- `build-local-snapshot.sh` detecta huérfanos en `.opencode/scripts/`
  (antes solo lo hacía el test, no el script real que usan el doctor y CI).
- `tests/setup.test.sh` deja de crear su DB de fixture con
  `sqlite3 ... < project-schema.sql` directo (bypasseaba `teamdb-init.sh`,
  sin migrations aplicadas ni versión validada); usa el init real.

### Security
- Gate de CI `lint-sqli.yml`: primera corrida real dio 44 blockers sobre
  código ya existente en el repo → 0. El heurístico de "secreto
  hardcodeado" marcaba `token=?` (el placeholder seguro de bind params) y
  valores generados en runtime como secretos; corregido y verificado
  contra falsos y verdaderos positivos de control.

### Added
- `scripts/.bundle-manifest` + `scripts/build-local-snapshot.sh`
  (`--apply/--check/--dry-run`) para mantener sincronizados `scripts/` y
  `.opencode/scripts/`, con `tests/scripts-parity.test.sh` en CI.
- Marcador `# lens:ok <motivo>` en `skalling-review.sh` para excepciones
  puntuales por línea (el motivo queda en el diff, no en un YAML aparte).
- `rm_targets_are_mktemp()`: reconoce variables asignadas vía `mktemp`
  como guarda válida en el lens de riesgo, en vez de exigir un chequeo
  redundante sobre algo seguro por construcción.

### Removed
- `teamdb-claim-task.sh` (CAS simple sobre `tasks.status/version`, sin
  expiración de lease): sin ningún caller real (ningún agente ni skill lo
  invocaba) desde antes de esta auditoría. El ciclo de claims quedó
  unificado en `teamdb-claim.sh` (lease/epoch, `input_hash`, transiciones
  `in_review→approved`/`approved→resolved` verificadas por rol), que ya
  era lo único que usaban los 8 agentes y `teamdb-execute-plan.sh`.
  `task_lock_history` queda como superficie legacy de solo lectura, mismo
  tratamiento que `work_in_progress`/`code_graph_cache`.

### Migration
- `029_version_0_11_2.sql` eleva bases existentes a schema `0.11.2`.
- `030_deprecate_task_claim_task.sql` marca `task_lock_history` como
  `legacy_surface`.

## [0.11.1] — en preparación

### Fixed
- Flujo runtime con identidad de sesión, estados ordenados y evidencia independiente.
- Política de permisos generada desde una fuente única.

## [0.11.0] — pendiente de publicación

### Protección de datos
- Helpers SQLite protegidos contra DELETE, REPLACE, DROP, DDL destructivo y vaciado de contenido durable; consultas realmente read-only.
- Versiones anteriores del conocimiento conservadas en `data_revisions` dentro de TeamDB; no se exportan automáticamente a Git.
- Herramienta `teamdb_destructive`: aprobación nativa por operación exacta, respaldo previo y rechazo de aprobaciones sobre una base que cambió. No se concede este permiso mediante Goal.
- `cp` y `rm` genéricos mantienen aprobación; no se concede permiso ilimitado para sobrescribir o eliminar archivos.
- Pruebas antiguas de contratos y migración de planes aisladas en bases temporales; no operan sobre la TeamDB del checkout.
- Los controles cubren los helpers distribuidos; no sustituyen permisos del sistema operativo ni protegen otras bases frente a programas externos ejecutados fuera de ellos.

### Added
- `/skalling-goal`: consentimiento explícito para un commit local, estado por sesión en TeamDB y continuación mediante plugin de OpenCode. Sin push ni despliegue; pausa, reanudación, cancelación y límites de progreso.
- Cierre del objetivo con protección de archivos previos, rama/HEAD, lista explícita y evidencia del candidato staged.

### Fixed
- Permisos de lectura, pruebas y helpers de TeamDB de los ocho agentes con precedencia correcta y rutas canónicas. Shell/SQL arbitrarios y publicación siguen sujetos a aprobación.
- Cierre Git de solo lectura: revisa únicamente el candidato staged, sin caducidad temporal ni regeneración automática del dump en hooks.
- Push comprueba cada commit pendiente contra su evidencia aprobada, no contra el último comprobante de toda la base.
- Detección de secretos sobre los cambios que se publican y errores explícitos, sin limpieza automática de memoria ni comprobantes retroactivos.

## [0.10.4] — 2026-09-08

### Fixed
- Cápsulas con pedido obligatorio, selección por relevancia, reglas completas y omisiones explícitas.
- Bootstrap DB-first sin carpetas Markdown automáticas; preserva conocimiento existente y detecta comandos reales de pruebas.
- Estado initialized separado de comprensión de tarea; routing exige contexto y plan aprobado cuando corresponde.
- Contratos y ejemplos de Alex/Sol/Teo, ciclo y guía visual alineados; lectura de fuentes y reutilización obligatorias.
- Archivo recuperable de memoria Markdown legacy y exportación explícita desde TeamDB.
- Pruebas de regresión de contexto, contratos y preservación de memoria.
- Clasificación con intención obligatoria; investigar y auditar no autoriza implementar.
- Refresh actualiza datos autogenerados intactos y conserva ediciones humanas con observaciones pendientes en DB.
- Guía de planificación con comandos ejecutables verificados e instalación aislada con backups en su destino configurado.
- Prueba del paquete instalado: bootstrap, refresh, contexto visual, planificación, aprobación y selección de tarea.

## [0.10.3] — 2026-09-07

### Fixed
- `/skalling-init` ahora hidrata contexto real, indexa CodeGraph, siembra TeamDB y solo declara `READY` cuando las comprobaciones semánticas pasan.
- El routing bloquea implementación y deriva a descubrimiento cuando la memoria del proyecto falta o está degradada.
- Los cambios visuales suben como mínimo a flujo `INLINE`; Alex y Teo deben respetar el sistema de diseño y el alcance aprobado.
- Routing unificado por riesgo e impacto; alcance desconocido, áreas sensibles y decisiones pendientes impiden atajos a Teo. Reclasificación obligatoria ante nueva evidencia.
- Los ocho agentes exigen consentimiento explícito de sesión para push/deploy y escalan decisiones críticas al usuario.
- Instalación global actualiza el contenido de skills existentes sin anidar otra copia y dejar activa la versión anterior.
- Pruebas de regresión para alcance, seguridad, decisiones humanas e intención de solo lectura.

## [0.10.2] — 2026-09-04

### Added
- Dashboard operativo de solo lectura con estado, flujo, agentes, próximos pasos, historial y actualización automática.
- Política reutilizable de retención para respaldos administrados de TeamDB.
- Persistencia opcional en una sola operación de clasificación, routing y métricas iniciales.
- Licencia MIT explícita en la raíz del proyecto.

### Changed
- CI ejecuta la suite completa, las pruebas del dashboard y el doctor en modo estricto sobre una instalación limpia.
- El doctor excluye respaldos y directorios legacy al revisar documentos de memoria.
- `work_in_progress` queda declarado como superficie legacy de compatibilidad; el ciclo canónico continúa en `plans` y `tasks`.
- Documentación de comandos, reglas y pruebas sincronizada con el estado real del repositorio.

### Security
- `teamdb-claim-task.sh`, el hook precommit y el registro de routing usan parámetros enlazados en vez de interpolar entradas en SQL.
- Las migraciones legacy dejan de ocultar errores de SQLite.

### Migration
- `023_version_0_10_2.sql` identifica la superficie legacy y eleva bases existentes a schema `0.10.2` sin eliminar datos.

## [0.10.1] — 2026-09-04

### Added
- `/skalling-help`, `/skalling-memory`, `/skalling-metrics`, `/skalling-resume` y `/skalling-recover` cubren descubrimiento, memoria unificada, medición, continuidad y recuperación segura.
- `teamdb-resume.sh` entrega una cápsula de trabajo activa, acotada y de solo lectura.

### Changed
- Los comandos son contratos pequeños que delegan en scripts canónicos instalados, sin SQL directo ni rutas dependientes del checkout.
- Memoria, grafo y revisión se consolidan en `/skalling-memory`; la asignación automática de modelos queda desactivada hasta disponer de configuración independiente por agente.
- El instalador publica bootstrap, doctor, actualizador y dependencias de detección en rutas globales estables.
- Dashboard abre el navegador en macOS, Linux, WSL y Git Bash; update conserva backups y rechaza repos con cambios locales.

### Migration
- `022_version_0_10_1.sql` eleva bases existentes a schema `0.10.1`; no modifica tablas ni datos.

## [0.10.0] — 2026-09-03

### Added
- **Flujo adaptativo por riesgo**: Alex clasifica cada solicitud como `low`, `medium` o `high` y selecciona una ruta proporcional, evitando activar ocho agentes para cambios pequeños.
- **Cápsulas económicas de contexto**: `teamdb-context.sh for-request` recupera memoria relevante con límite de tamaño e incluye siempre el resumen general del proyecto.
- **Telemetría operativa**: `skalling-metrics.sh` registra ruta, agentes, handoffs, permisos, bytes de contexto, duración y resultado sin afirmar ahorro de tokens que el runtime no mida.
- **Métricas persistentes**: nueva tabla `workflow_metrics` y migraciones `020_workflow_metrics.sql` y `021_version_0_10_0.sql`.
- **Acceso seguro a TeamDB**: nuevos helpers tipados `teamdb-read.sh` y `teamdb-memory.sh`, sin SQL mutante arbitrario desde prompts.

### Changed
- Verificación de Jhon proporcional al riesgo; cierre de Pau solo persiste memoria y documentación cuando hay conocimiento durable.
- Inicio de sesión prioriza automáticamente la base del proyecto y los handoffs admiten riesgo, ruta y cápsula compartida.
- Prompts de agentes y permisos alineados con el modelo DB-first para reducir solicitudes repetidas de autorización.
- **Contratos compactos de los 8 agentes**: prompts operativos reducidos de 97.612 a 42.924 bytes; responsabilidades, entradas, salidas y criterios de escalación quedan explícitos sin reglas duplicadas.
- **Render único de agentes**: instalación global y por proyecto usan `scripts/render-agent.sh`, evitando drift entre `agents-base/` y `.opencode/agents/`.
- **Instalación multiplataforma endurecida**: preflight obligatorio de SQLite/Python, SHA-256 portable y wrappers PowerShell con selección explícita entre Git Bash y WSL, rutas configurables y paridad de desinstalación.

### Fixed
- YAML inválido en agentes, SQL directo en prompts, temporales sin limpiar en `teamdb-plan.sh` y conservación incorrecta de una versión antigua durante el saneamiento global.
- Contradicciones de permisos/acciones en los ocho agentes, recuperación destructiva de TeamDB, ownership ambiguo Pol→Sol y quality gates absolutos que producían bloqueos falsos.
- La CI ahora ejecuta instalaciones completas en macOS, Linux y Windows y prueba el wrapper PowerShell; se eliminó la matriz que rotulaba Bash 3/4/5 sin instalar esas versiones.

### Migration
- `020_workflow_metrics.sql` crea la telemetría operativa.
- `021_version_0_10_0.sql` eleva bases existentes a schema `0.10.0`, incluso si la migración 020 ya había sido aplicada.

## [0.9.2] — 2026-08-18

### Fixed
- **DB-First enforcement en Sol**: bloque `⛔ REGLA ABSOLUTA — DB-FIRST NO NEGOCIABLE` agregado arriba del PASO 1 del protocolo. Obliga a verificar `team.db` antes de planificar, prohíbe editar `.md` en `.opencode/changes/<slug>/`, y define la "violación detectable" (artefacto sin fila en DB) que Pau auditara.
- **Delegación forzada en Alex**: bloque `⛔ REGLA ABSOLUTA — DELEGACIÓN NO NEGOCIABLE` agregado debajo de la tabla de despacho. Prohíbe que el orquestador edite `.opencode/changes/<slug>/SPEC.md | PLAN.md | TASKS.md` directamente — debe delegar a Sol.

### Problema cerrado
Sesiones que pedían "plan X" generaban `.md` huérfanos en `.opencode/changes/<slug>/` mientras `team.db` quedaba vacía para ese slug. El modelo ejecutaba el contrato SDD legacy (filesystem-first) en lugar del flujo Skalling DB-first.

### Migración
- Ninguna. Cambio solo de prompts; no toca schema ni scripts.

## [0.9.1] — 2026-08-08

### Fixed
- **workflow_state en DB**: tabla singleton `workflow_state` reemplaza `.opencode/state/workflow.json`. Init ya no crea `.opencode/state/`. Agentescoordina ciclo activo via DB, no archivos. Cierra el ciclo DB-first.

### Migration
- `017_workflow_state.sql` para DBs existentes.

## [0.9.0] — 2026-08-08

### Added
- **Fase 0 — Dump por fila mergeable**: dump versionado por fila (`teamdb-dump.sh --by-row`), `teamdb-merge.sh` aplica filas una a una con clave primaria estable, backup antes de merge, audit_log de decisiones.
- **Fase 1 — Dump fresco post-escritura + gates baratos**: scripts de escritura regeneran dump automáticamente; pre-commit compara hash (O(1)); pre-push valida dump==DB y receipt.
- **Fase 2 — Estados y fechas**: columna `due_date` en tasks (migration 016), `teamdb-status.sh` muestra `[OVERDUE]`, circuito de estados `pending→in_progress→in_review→approved/resolved`.
- **Fase 3 — Agentes DB-first real**: skill `skalling-cycle` reescrito a DB-first (la DB es fuente de verdad, no filesystem); 7 agentes actualizados para usar `teamdb-plan.sh`, `teamdb-claim.sh`, `teamdb-status.sh`, `teamdb-seal-receipt.sh` en vez de SQL crudo y tabla legacy `work_in_progress`.
- **Fase 4 — Puente .opencode/changes↔DB**: nuevo script `teamdb-ingest-change.sh` ingiere un change dir completo (proposal.md + tasks.md + specs/*.md + design.md) a la DB de forma idempotente y atómica; `teamdb-export-md.sh` extiende para regenerar `specs/*.md` desde la tabla `specs`; gate de lifecycle en `teamdb-execute-plan.sh` (solo acepta planes `approved` o `in_progress`).
- **Skill `skalling-cycle` DB-first**: el ciclo ahora enseña a consultar/escribir en la DB con los scripts del circuito, no con archivos `.opencode/changes/`.
- **Test suite expandida**: 46 tests en `teamdb-hardening-suite.sh`.

### Fixed
- **Test setup.test.sh**: versión hardcodeada `0.7.8` → `0.9.0`.

### Migration
- `016_add_due_date.sql` para DBs existentes.

## [0.8.2] — 2026-08-07

### Fixed
- **Race conditions**: flock en 18 scripts teamdb-* (protege multi-writer)
- **SQL injection**: escape de slug en migrate-plans-md-to-db.sh
- **Timeouts**: helper teamdb-with-timeout.sh + validación con timeout en init
- **Sin tracking de tiempo**: columna estimated_minutes en tasks
- **Sin límite de delegación**: regla R-NEW en Alex (max 3 niveles)
- **Sin TTL en cache**: teamdb-context-cache.sh (TTL 30 min)
- **Receipts sin validación**: comando + exit_code al claim

### Migration
- `013_add_time_tracking.sql` para DBs existentes

## [0.8.0] — 2026-08-07

### Added
- **RDD con receipts**: pre-commit hook valida receipts recientes (<10 min) si hay cambios en código
- **CAS (compare-and-swap)**: tasks usan `version` + `locked_by` para evitar race conditions
- **Tabla `task_lock_history`**: audit de claims/locks
- **Claim con script**: `teamdb-claim-task.sh` hace CAS atómico
- **Fail-closed**: `teamdb-init.sh` aborta si DB corrupta o faltan tablas críticas
- **Backup dedupe + prune**: install-global.sh ya no crea backups idénticos

### Migration
- `012_add_cas.sql` para DBs existentes

### Changed
- Pre-commit hook ahora es fail-closed en receipt ausente
- `install-global.sh` prune_old_backups() ahora respeta dedupe

## [0.7.9] — 2026-08-07

### Added
- Tabla `routing_decisions` — audita decisiones de ruta de Alex
- Tabla `receipts` — evidencia de completitud (command, exit_code, output)
- Alex registra decisiones de routing en DB
- Pre-commit hook valida que no haya tasks in_progress sin cerrar
- Doctor chequea receipts y routing_decisions

### Migration
- `sql/migrations/011_add_routing_receipts.sql` para DBs existentes

## [0.7.4] — 2026-08-05

### Added
- **Grafo de memoria auto-enlazado**: `scripts/teamdb-link.sh` crea los links de `memory_links` que el grafo ya sabía dibujar pero nadie poblaba. Reglas: `related` entre conceptos de la misma categoría, `related` entre conceptos/decisiones que comparten tag, y `uses` de conceptos no-stack → conceptos de categoría `stack`. Idempotente (no duplica), escribe con audit (`teamdb_write_project`), soporta `--dry-run`.
- **Comando `/skalling-graph`**: protocolo para visualizar la memoria como grafo (link + graph en text/mermaid/dot + related + search), con el mismo estilo de `/skalling-init`.
- **Migración `006_link_graph.sql`** (marca schema v0.7.4; el schema no cambia).
- **`/skalling-init` ahora enlaza el grafo** tras crear la DB, y deja de preguntar por codebase-memory-mcp (paso 4.7 eliminado): con el grafo de teamdb la red del proyecto se arma sola. El MCP sigue disponible como opt-in manual.

### Changed
- `teamdb-link.sh` usa los writes audited del helper (`audit_log` con `actor_source='helper'`).

## [0.7.3] — 2026-08-05

### Added
- **Skills registry (índice, no contenido)**: las skills siguen viviendo como archivos `SKILL.md`, pero ahora la DB guarda la ficha de cada una (`name`, `description`, `version`, `source`, `load_path`) en `skills_active` (global) y `skills_registry` (por proyecto). Preguntás "¿qué skills tiene este proyecto y para qué sirven?" → query a la DB, no adivinar.
- **`scripts/teamdb-skills-sync.sh`**: indexa skills desde `skills-lock.json`, `.opencode/skills`, `~/.agents/skills` y `$OPENCODE_DIR/skills`, extrayendo metadata del frontmatter de `SKILL.md`. Idempotente (upsert por nombre).
- **Migración `005_add_skills_registry.sql`** (`skills_registry` en schema de proyecto) + columnas `description`/`load_path` en `skills_active` (schema global, añadidas idempotentemente por `teamdb_heal_global`).
- **Wiring**: `install-global.sh` corre el sync global al instalar; `/skalling-init` (paso 4.4) indexa las skills del proyecto.
- **`skalling-init`**: resuelve la raíz de instalación (`$SK_ROOT`, repo o `~/.config/opencode`) y busca hooks en `$OPENCODE_DIR/hooks` — corrige el bootstrap cuando `SKALLING_ROOT` no está definido y no rompe el `team.db` existente (ver Fixes).

### Fixed
- `skalling-init` (v0.7.2) destruía `team.db` si el schema no era `0.7.0` exacto: ahora migra con `teamdb-init.sh` (idempotente, nunca borra).
- `skalling-init` (v0.7.2) no encontraba `teamdb-*.sh` ni los hooks git por referencias a `$(dirname "$SKALLING_ROOT")` con la variable sin definir: ahora usa `$SK_ROOT` resuelto.

## [0.7.2] — 2026-08-05

### Added
- **Ciclo de planificación en DB**: `scripts/teamdb-plan.sh` (crea filas en `proposals`, `plans`, `tasks`), `teamdb-status.sh` (resume del plan activo), `teamdb-resume.sh`, `teamdb-execute-plan.sh` (descubre/orquesta la próxima task; NO ejecuta shell arbitrario desde la DB — DC-3), `teamdb-amend.sh` (amendment atómico in-place con version/historial en `plan_history` y preservación de tasks aprobadas como inmutables), `teamdb-deps.sh` (DAG con `task_dependencies`, detección de ciclos y query `runnable`), `teamdb-claim.sh` (claim atómico con lease/attempt/input_hash + resume), `teamdb-context.sh` (context capsules para handoff de Teo), `teamdb-export-md.sh` (markdown GENERADO desde DB, sin escritura bidireccional)
- **Tablas nuevas** en `sql/project-schema.sql` (migration `003_add_dag_claims_history.sql`): `task_dependencies`, `task_claims`, `plan_history`, `task_context_capsules`
- **SQL parametrizado real**: `scripts/teamdb_exec.py` (wrapper Python `sqlite3` con bound params) — `teamdb_safe_query` queda deprecated. Escrituras con transacciones `BEGIN IMMEDIATE` + WAL + `busy_timeout` en `teamdb_write_project`/`teamdb_write_global` (reemplaza flock)
- **FTS5 para `known_problems`**: virtual table `problems_fts` + triggers sync (`teamdb-search.sh` la usa)
- **Snippets single-source (DC-2)**: markers `@include-snippet` en los 8 agentes, resolución build-time en `install-global.sh::resolve_snippets`; canónicos en `templates/agents/snippets/`
- **Handoff schema condicional**: `templates/handoff.schema.json` con `allOf` if/then — `project_context` required cuando `to` ∈ {TEO, LUZ}; `verification` required cuando `to` ∈ {JHON, LUZ} (o emisor de ingeniería)
- **`audit_log.actor_source`**: columna nueva (`'helper'` vía `teamdb_write_*`, `'trigger'` en 12 triggers reescritos); plumbing de `TEAMDB_ACTOR`
- **CI**: `.github/workflows/tests.yml` ampliado con 22 suites teamdb + 3 workflows nuevos (`teamdb-sqli.yml`, `handoffs.yml`, `teamdb-dag-claims.yml`) = 4 workflows en cada PR
- **Suite agregadora** `tests/teamdb-hardening-suite.sh` (regresión completa 45/45)
- **Tests nuevos**: version-coherence, portability-bash32, snippets-sync, install-resolves-snippets, handoff-schema-validation, agents-teamdb-integration, dag-tables, amend-full, deps-dag, claim-lease/strict/history, export-md, context-capsule/issue8, cycle-amended, execute-plan-no-shell, migration-003-unique, plan-atomic-idempotent, python-bindparams, write-wal, export-audit, migrate-md-preserve

### Changed
- `scripts/teamdb-search.sh` y `teamdb-related.sh` parametrizados (sin interpolación; whitelist de tipos en related)
- `agents-base/Alex.md` y `agents-base/Jes.md`: TeamDB preferente para cargar contexto (fallback legacy)
- `scripts/teamdb-migrate.sh`: SQL parametrizado + preserva `.md` (solo mueve `.jsonl` a `legacy/` — DC-1)
- `scripts/teamdb-export.sh` exporta también `audit_log` y `schema_meta`
- `scripts/build-schema.sh` (nuevo): estampa SOLO la fila `schema_meta.version` desde `VERSION` (AD-4 corregido)
- Hooks `pre-commit`/`post-merge`: resuelven paths absolutos con `git rev-parse --show-toplevel` (sin `$SCRIPT_DIR/../`)
- `install-global.sh`: instala todos los `teamdb-*.sh` dinámicamente + hooks ejecutables sin `|| true` silenciadores

### Fixed
- **SQL injection** en `teamdb-search.sh` y `teamdb-related.sh`: entradas del usuario pasan por bound params reales (Python `sqlite3`), no escape manual
- Fixes del quality gate de Luz (H1/H2/M1-M5, commit `cfbf3f3`) y fix menor de handoff-schema (`6ad8944`): el test de schema deja de saltar silenciosamente si `jsonschema` falta

## [0.7.0] — 2026-08-05

### Added
- **libSQL como fuente de verdad**: 2 DBs (global + proyecto) con esquema formal
- **Schema global** (`sql/global-schema.sql`): 8 tablas para agents_meta, skills_active, constitution_rules, user_preferences, stack_cache, projects_index
- **Schema proyecto** (`sql/project-schema.sql`): 12 tablas + FTS5 + triggers para concepts, decisions, preferences, known_problems, work_in_progress, memory_tags, memory_links, audit_log
- **Jerarquía plan/feature/task** en `work_in_progress` (columnas `type`, `parent_id`)
- **Grafo de relaciones**: `memory_links` (extends/contradicts/uses/supersedes/related) + `memory_tags`
- **FTS5**: búsqueda full-text en conceptos, decisiones y WIP
- **Triggers automáticos**: mantienen FTS5 sincronizado con tablas base
- **Audit log automático**: registra cada cambio
- **lib-teamdb.sh**: wrapper bash con `flock` para multi-writer seguro
- **teamdb-init.sh**: inicializa DB proyecto
- **teamdb-migrate.sh**: migra `.jsonl` legacy a DB
- **teamdb-export.sh**: DB → `.sql` para git
- **teamdb-import.sh**: `.sql` → DB
- **wip-tree.sh**: visualizador recursivo plan/feature/task con estados derivados
- **30 tests** en `tests/teamdb.test.sh` (8 schemas + 7 scripts + 5 E2E + 7 FTS5/jerarquía + 3 fixes audit/migrate/import)

### Changed
- `install-global.sh`: instala teamdb global (DB + scripts)
- `bootstrap-context.sh`: inicializa teamdb proyecto
- `Pau.md`: documenta uso real de teamdb con queries

### Fixed
- **SQL injection en `teamdb-migrate.sh`**: helper `sql_escape` con `sed "s/'/''/g"` aplicado a todos los campos JSON antes de interpolación SQL. Migración segura de `.jsonl` legacy.
- **Audit log triggers implementados**: 12 triggers (4 tablas × INSERT/UPDATE/DELETE) registran cada cambio en `audit_log` con timestamp, agent, action, table, row_id y details en JSON.
- **flock wrappea escrituras (`teamdb_write_project`)**: nueva función en `lib-teamdb.sh` que toma lock de flock con timeout 5s antes de ejecutar INSERT/UPDATE/DELETE. Previene race conditions en escrituras concurrentes. Usada en `teamdb-migrate.sh`.
- **Import en DB existente**: `teamdb-import.sh` ahora extrae solo líneas `INSERT INTO` del dump SQL (con `grep -E "^INSERT INTO "`), evitando conflicto con `CREATE TABLE` que ya existe. Importa idempotentemente con warnings por tabla que falle.
- **`install-global.sh` lee VERSION dinámico**: ya no tiene `SKALLING_VERSION="0.6.2"` hardcodeado; lee de `VERSION` file via `grep '__version__' | sed`. Mismo fix en `setup-team-doctor.sh`.
- **Doctor chequea teamdb**: nueva sección `check_teamdb()` valida `team.db` global y per-project contra VERSION, y verifica que los 12 audit triggers estén activos. Advierte si hay mismatch.
- **`.gitattributes` para `.sql` merge**: `data_*.sql` usa `merge=union` (cada INSERT es idempotente, conservar ambas líneas es seguro).
- **Hooks se activan automáticamente**: `bootstrap-context.sh` llama nueva función `activate_teamdb_hooks()` que copia `pre-commit` y `post-merge` a `.git/hooks/` y los hace ejecutables.
- **`wip-tree.sh` SQL escape**: helper `sql_escape` aplicado a `parent_slug` antes de la query. Previene crash cuando un slug contiene comillas.
- **`post-merge` no suprime errores**: removido `2>/dev/null || true`. Errores de import ahora son visibles en consola (la salud de teamdb es importante).

### Removed
- `sql/migrations/001_add_wip_hierarchy.sql`: dead code. La jerarquía `type`/`parent_id` ya está en `sql/project-schema.sql` desde v0.7.0 inicial. Directorio `sql/migrations/` vacío eliminado.

### Migration Guide v0.6.x → v0.7.0
1. `git pull origin teamdb`
2. `bash install-global.sh` (instala teamdb global automáticamente)
3. Por cada proyecto: `bash bootstrap-context.sh` (crea team.db proyecto + activa hooks)
4. Los archivos `.jsonl` legacy se migran automáticamente a la DB
5. Verificar instalación: `bash setup-team-doctor.sh`

## [0.6.2] — 2026-08-04

### Changed
- **Refactor de Alex (orquestador)**: delegación directa por rol. Eliminada la fricción de pedir permiso antes de delegar a otros agentes. Nueva tabla de despacho intención → agente → permiso en `agents-base/Alex.md`. Catch-all refactorizado para preguntar QUÉ quiere el usuario, no QUÉ agente.
- **Anti-patrones explícitos en Alex**: ya no pregunta "¿te parece bien?" antes de delegar, ni ofrece opciones de agente, ni repite el trabajo del equipo.
- **R16 reforzado**: Alex escribe el mensaje del commit en español siguiendo Conventional Commits.

### Fixed
- Bundle global: install-global.sh ahora copia `scripts/spec-memory-link.sh` y `scripts/skalling-drift.sh` (v0.6.1 ya había intentado el fix pero quedó incompleto hasta aquí).

## [0.6.0] — 2026-08-04

### Added
- **`scripts/spec-memory-link.sh`**: CLI de Pau para enlazar concept docs (`docs/`, `.opencode/context/concept/*.md`) a la spec archivada que los originó. Detecta paths literales en `proposal.md`, `design.md`, `tasks.md` y `specs/*.md` mediante el regex `\.opencode/context/concept/[A-Za-z0-9._-]+\.md`, descarta matches con traversal/espacios/nombre vacío, valida existencia, deduplica y aplica un footer `## Spec original` con link relativo hardcodeado (`../../changes/archive/<YYYY-MM>/<slug>/`) al path final del plan. Escritura atómica con `mktemp` + `mv`; idempotente (segundo run preserva el primero); portable con Bash 3.2.
- **`tests/spec-memory-link.test.sh`**: cobertura autocontenida de estructura, argv inválido, detección por archivo, regex con/sin prefijo repo, deduplicación, validación de path, cálculo de path relativo, formato exacto del footer, idempotencia 2-run y 3-run, preservación del primero, errores por archivo, integración con Pau, integración informativa del doctor, portabilidad Bash 3.2 e identificadores R1.
- **Integración informativa del doctor**: línea `ℹ` (azul, no bloqueante) sobre la disponibilidad de `scripts/spec-memory-link.sh` agregada al final de la sección de instalación per-project; mantiene el exit code 0 normal y bajo `--strict` mientras no haya otros findings propios.
- **Documentación**: nuevo párrafo en `README.md` describiendo Spec ↔ Memory link y fila en la tabla de salida de `command/skalling-doctor.md` con nota sobre ejecución manual.

### Changed
- `agents-base/Pau.md`: PASO 5 extendido con sub-paso explícito de invocar el script antes del `git mv`, y reporte final al usuario listando los concept docs enlazados (omitiendo la sección si la lista está vacía). Permisos y resto del PASO 5 intactos.

## [0.5.0] — 2026-08-04

### Added
- **`scripts/skalling-drift.sh`**: CLI de solo lectura para detectar drift entre claims declarados en specs archivadas y el estado actual del repositorio.
- **Verificadores declarativos**: soporte para existencia de archivos, conteo no recursivo y presencia de texto literal mediante claims `archivo`, `count` y `contiene`.
- **Validación defensiva**: rechazo de claims malformados, paths absolutos, traversal y espacios, con límites de bloque y advertencias no bloqueantes.
- **`tests/skalling-drift.test.sh`**: cobertura autocontenida de casos exitosos, drift mixto, errores de entrada, TTY, límites, portabilidad Bash 3.2 e identificadores R1.
- **Integración con doctor**: línea informativa azul y no bloqueante que indica cómo ejecutar drift detection manualmente, documentada en `command/skalling-doctor.md`.

## [0.4.0] — 2026-08-04

### Added
- **Codebase-memory-mcp como feature opt-in**: integración con [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (servidor MCP de inteligencia estructural de código). NO es dependencia dura — se ofrece como paso 4.7 en `/skalling-init`.
- **Snippet canónico `templates/agents/snippets/code-intelligence.md`**: single source con guía de cuándo usar las 5 tools (`trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`).
- **Inyección en los 8 agentes**: sección `## 🔍 Code Intelligence` agregada antes de `## 🧠 Memory Protocol`, con comment block `SINCRONIZADO CON:`.
- **Paso 4.7 en `/skalling-init`**: pregunta al usuario si quiere instalar codebase-memory-mcp; 3 ramas (Sí/No/ya-instalado).
- **`check_code_intelligence()` en el doctor**: verifica instalación y configuración del MCP server como info (no bloquea).

### Changed
- `command/skalling-init.md`: paso 4.7 nuevo.
- `setup-team-doctor.sh`: nueva función informativa de Code Intelligence.
- Tests: 3 archivos de prueba nuevos (`tests/code-intelligence.test.sh` con 44 asserts + `tests/doctor-code-intelligence.test.sh` con 13 asserts + `tests/doctor-strict-environment.test.sh` con 7 asserts = 64 asserts nuevos, 345 PASS total).

### Security
- El comando de instalación verifica SHA-256 contra `checksums.txt` del tag fijo antes de ejecutar; aborta con `exit 1` si el checksum no coincide.

## [0.3.0] — 2026-08-04

### Added
- **Concept template What/Why/Where/Learned**: reescrito `templates/okf/concept.template.md` con 4 secciones obligatorias; Pau rechaza docs nuevos sin las 4 secciones (PASO 4 de validación previa al archivo).
- **Memory Protocol snippet**: snippet canónico en `templates/agents/snippets/memory-protocol.md` inyectado en los 8 agentes (`## 🧠 Memory Protocol`) con comment block `SINCRONIZADO CON` para mantenimiento; Pau tiene bloque de consolidación extendido.
- **Conflict detection en Pol**: nueva FASE 5 en `agents-base/Pol.md` que lee concept docs y trabajo-en-curso antes de cerrar la proposal, con 3 escenarios (sin conflictos, con conflictos marcados en `## ⚠️ Conflictos detectados`, bundle corrupto salta el check sin bloquear).
- **`/skalling-forget` con consolidación**: comando reescrito para invocar `mem-review` primero y ofrecer opciones A/B/C/D por candidato (archivar, marcar superseded, consolidar, mantener); log en `.opencode/context/log.md`.
- **`scripts/mem-review.sh`**: nuevo script diagnóstico (duplicados → WIP zombie >30d → stale >6m → superseded) basado en `scripts/lib/lib-memory-check.sh`.
- **`scripts/lib/lib-memory-check.sh`**: helper sourceable con 6 funciones (`skalling_parse_yaml_field`, `skalling_find_orphans`, `skalling_find_zombie_wip`, `skalling_find_duplicates`, `skalling_find_stale`, `skalling_find_superseded`); umbrales configurables via `SKALLING_WIP_ZOMBIE_DAYS` (default 30) y `SKALLING_STALE_MONTHS` (default 6).
- **Sección Memoria en `setup-team-doctor.sh`**: nueva función `check_memory_health()` con 5 chequeos del bundle OKF (huérfanos, WIP zombie, duplicados, stale, superseded vigente).

### Changed
- Doctor: output con nueva fila "Memoria (bundle OKF)" y 5 chequeos automáticos.
- Tests: cobertura completa de las nuevas features (8 tests nuevos, 281 PASS total en regresión).

### Security
- Ningún cambio de superficie de seguridad.

## [0.2.2] — 2026-08-03

### Fixed
- **Falso positivo de `update.sh` en `setup-team-doctor.sh`**: el check usaba una ruta hardcodeada (`$OPENCODE_DIR/../skalling-dev-team/scripts/update.sh`) que asumía el repo viviendo en `~/.config/skalling-dev-team/`. Ahora usa `$SCRIPT_DIR/scripts/update.sh`, basada en la ubicación real del script
- **Banner del instalador**: `install-global.sh` mostraba v0.1.0 hardcodeado. Ahora `SKALLING_VERSION="0.2.2"`

## [0.2.1] — 2026-08-03

### Added
- **Auditoría de Luz aplicada a los 8 agentes**: agentes reescritos con protocolos de escalación, evidencia de verificación y consistencia entre prompts y permisos
- **Teo**: receipts con evidencia (`verification`: comando exacto, exit code y output real) en todo handoff a Jhon; límite de 3 iteraciones en el loop Teo ↔ Jhon (escala a Alex, nunca bloquea en silencio); skills de UI condicionadas al stack del proyecto (solo carga si el framework lo requiere)
- **Alex**: protocolo de escalación con límites por fase (Teo↔Jhon 3, Jhon↔Luz 3, Luz↔Pau 2) y notificación al usuario con opciones A/B/C/D; relay de preguntas subagente → usuario (una a la vez, espera la respuesta y la reinyecta); receipts por ruta (`skalling-receipt`); protocolo R16.4 (muestra archivos y mensaje antes del commit); protocolo de negativa fundamentada ante pedidos que violan la constitución
- **Pol**: relay mode (devuelve preguntas a Alex en formato A/B/C/D, nunca espera respuesta directa del usuario); límite de 3 rondas de preguntas por feature (propone con lo que hay y marca suposiciones); triviales → fast-track a Teo sin plan
- **Pau**: dueña del design-system (R13 — fuente de verdad en `.opencode/context/proyecto/design-system.md`); schema OKF completo (catálogo de 6 tipos + frontmatter obligatorio); ownership de archive (mueve changes completados a `.opencode/changes/archive/<YYYY-MM>/`)
- **Jhon**: `project_context` obligatorio en handoff a Luz; validación de receipts de Teo antes de re-ejecutar; umbral de coverage 80%
- **Sol**: pipeline mode (planifica la feature N+1 mientras Teo ejecuta la N)
- **Luz**: chequeo R13 (coherencia con `design-system.md`); checklist de evidencia con exit codes esperados (eslint, tsc, prettier, npm audit, impeccable); `websearch` para verificar CVEs reales antes de aprobar/rechazar dependencias
- **Jes**: PASO 0 — lee el bundle OKF (concept docs) antes de explicar; usa `websearch` para afirmar hechos externos
- `templates/handoff.schema.json`: campo `verification` (type, command, output_summary, exit_code, tests_total/passed/failed)

### Changed
- Los 8 agentes (`agents-base/*.md`) reescritos según las recomendaciones de la auditoría de Luz
- **Teo**: R16 — commits requieren consentimiento explícito del usuario; permisos `git add*`/`git commit*` en `ask` (antes solo `git push*`)
- **Alex**: Session Start Protocol lee concept docs del bundle OKF (YAML) en lugar de memorias `.jsonl`; permisos ampliados a `.opencode/changes/**/receipts/*.json`
- **Jes**: contradicciones resueltas — la tabla gana: pregunta conceptual → responde directo; hecho externo → busca primero
- **Pol**: sin límite de rondas → máximo 3 (nunca bloquea el ciclo por perfeccionismo)
- **Sol**: lee `.opencode/project.yaml` con la herramienta de lectura (no bash — permiso `bash: deny`); granularidad de tareas ~30 min (unidad verificable por Jhon); archiving delegado a Pau (antes lo hacía Sol)
- **Luz**: valida `project_context` del handoff de Jhon antes de arrancar; veredictos con exit code real de cada comando ejecutado
- `skills-base/skalling-handoff/SKILL.md`: ejemplo de Approval Handoff corregido con `project_context`
- **README**: simplificado y reescrito en lenguaje simple (antes técnico y extenso)

## [0.2.0] — 2026-08-03

### Added
- **`skalling-routing`**: Formato Gentle-AI con Hard Rules + Decision Gates. 6 rutas: INLINE, INTERVENTION, FAST-TRACK, SDD, DIRECT, RESEARCH
- **`skalling-receipt`**: Formaliza verificación en receipts JSON con receipt_id, verification types, delivery gates
- **`skalling-memory`**: Engram-style usando `.jsonl` locales (DECISIONS, PATTERNS, PREFERENCES, REJECTIONS). ~90% token savings
- **Alex actualizado**: Usa Decision Tree de routing, carga skalling-memory al inicio de sesión
- **Skills como core**: Los 3 nuevos skills instalados por `install-global.sh` (data-driven via `skills-by-stack.yaml`)

### Changed
- Alex.md: Detección de intención ahora usa Decision Tree en lugar de tabla estática
- Alex.md: Session Start Protocol carga memorias relevantes con grep

## [0.1.0] — 2026-07-28

### Added
- **Comando `/skalling-update`**: busca cambios en el repo remoto, muestra changelog, pide permiso y actualiza la instalación.
- **`scripts/update.sh`**: script bash para el update automático con confirmación del usuario.
- **R16**: commits requieren permiso explícito del usuario y mensajes descriptivos en español.
- **R13**: DESIGN.md reubicado de `docs/design/` a `.opencode/context/proyecto/design-system.md` (no se commitea).
- **Detección de intención de Alex**: tabla expandida con consulta directa, auditoría a Luz, operaciones git y catch-all con opciones.
- **Fase 13**: Regla R14 — Escalera de Ponytail (integrada de [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail))
- **Fase 12**: Bridge skill `skalling-impeccable-bridge` para integrar con [Impeccable](https://impeccable.style/)
- **Fase 11**: Comandos `/skalling-status`, `/skalling-refresh`, `/skalling-doctor`, `/skalling-forget`, `/skalling-merge`
- **Fase 8**: Memoria persistente por proyecto en formato [OKF v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf) con extensiones v0.2 (agent, confidence, supersedes)
- **Fase 8**: `bootstrap-context.sh` con detección data-driven desde `data/stack-detectors.yaml`
- **Fase 5**: 4 skills propios `skalling-*` (cycle, handoff, ponytail, impeccable-bridge)
- **Fase 4**: SDD formal con templates `proposal/spec/design/tasks` + JSON Schema para handoffs
- **Fase 3**: `install-global.sh` + `setup.sh` (idempotente con backup + dedup + prune)
- **Fase 3**: `setup-team-doctor.sh` para health check
- **Fase 15**: Regla R15 — Resolución de Conflictos Colaborativos vía `.gitattributes`
- **Fase 15**: `scripts/merge-helper.sh` + `command/skalling-merge.md`
- **Fase 11**: Wrappers PowerShell `.ps1` para Windows (`install-global.ps1`, `setup.ps1`, `bootstrap-context.ps1`, `setup-team-doctor.ps1`)
- **Fase 11**: `scripts/lib/lib-os.sh` con detección de OS (macOS, Linux, WSL, Git Bash, Windows)
- **Tests**: 130+ tests automatizados en `tests/setup.test.sh`
- **R14**: Constitución universal con 15 reglas (R1-R15)
- **R13**: DESIGN.md obligatorio para proyectos con interfaz gráfica
- **Pipeline Mode**: Sol puede planificar siguiente feature mientras Teo ejecuta la actual (parallelization)
- **`project_context` en handoff**: Schema actualizado para incluir stack, has_ui, design_system_exists, okf_bundle_valid

### Changed
- Frontmatter de agentes: `mode: primary|subagent`, `permission:` con reglas finas (reemplaza `tools:` deprecated)
- `Alex.md`: prompt magro (~150 líneas), Constitución separada
- `Sol.md` y `Teo.md`: paths corregidos a `.opencode/changes/<feature-slug>/` (antes `.opencode/plans/`)
- `Luz.md`: bash permission permite `npx impeccable *` (antes deny total)
- `setup.sh`: default = cwd con warning (antes directorio padre)
- `install-global.sh`: instala también `gitattributes.template`
- `Alex.md`: OKF Checkpoint obligatorio antes de derivar agentes (R12 enforcement)
- `Sol.md`: Handoff a Teo incluye `project_context` obligatorio
- `Teo.md`: Carga de contexto de proyecto obligatoria antes de implementar
- `skalling-handoff/SKILL.md`: Agregado Project Context Handoff como requerido
- `skalling-cycle/SKILL.md`: Agregado Pipeline Mode para parallelization
- `templates/handoff.schema.json`: Agregado `project_context` como propiedad opcional

### Removed
- `active.lock` (era documentación sin implementación)
- `data/stack-detectors.yaml` y `data/skills-by-stack.yaml` ahora son data files activos (antes eran documentación inerte)
- Flavor text "Frase Típica" de Alex.md

### Fixed
- Inconsistencia: Sol.md y Teo.md referenciaban `.opencode/plans/` legacy pero constitución R6 exigía `.opencode/changes/<feature-slug>/`
- Permisos: Luz tenía `bash: deny` pero prompt decía que ejecuta `npx impeccable`
- `set -u` crash con `$MSYSTEM` unbound en macOS — ahora usa `${MSYSTEM:-}`
- `sed -i.bak` no portable — reemplazado por `skalling_sed_inplace` (helper con macOS vs Linux)
- Bootstrap no detectaba correctamente stack desde YAML — ahora data-driven
- **Teo responde vacío**: Handoff ahora incluye `project_context` para transferir contexto del proyecto

## [0.1.0] — 2026-07-28

### Added
- Installer inicial con 8 agentes (Alex primary + 7 subagents)
- 14 skills base (test-driven-development, systematic-debugging, etc.)
- Constitución con 13 reglas base
- Templates OKF (6 tipos: Concept, Decision, Preference, Workaround, WorkInProgress, Context)
- `setup.sh` inicial (legacy, sin idempotencia)

[Unreleased]: https://github.com/alexskalling/skalling-dev-team/compare/v0.10.4...HEAD
[0.10.4]: https://github.com/alexskalling/skalling-dev-team/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/alexskalling/skalling-dev-team/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/alexskalling/skalling-dev-team/compare/v0.8.3...v0.10.2
[0.10.1]: https://github.com/alexskalling/skalling-dev-team/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/alexskalling/skalling-dev-team/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/alexskalling/skalling-dev-team/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.2...v0.8.3
[0.6.2]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/alexskalling/skalling-dev-team/releases/tag/v0.3.0
[0.2.2]: https://github.com/alexskalling/skalling-dev-team/releases/tag/v0.2.2
[0.2.1]: https://github.com/alexskalling/skalling-dev-team/releases/tag/v0.2.1
[0.1.0]: https://github.com/alexskalling/skalling-dev-team/releases/tag/v0.1.0
