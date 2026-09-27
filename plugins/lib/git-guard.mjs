// git-guard.mjs — guardia de comandos bash sensibles + identidad del agente.
//
// Por qué existe: data/permission-policy.json compara el comando COMPLETO
// contra globs. Una lista de patrones "ask" nunca cubre todas las formas de
// escribir lo mismo: `git add . && git push` matchea el allow de "git add *";
// `bash -c "git push"`, `command git push`, `/usr/bin/git push` o
// `git --git-dir=x push` no matchean ningún patrón y caen en "*": allow.
// Dos auditorías independientes encontraron esos bypasses uno tras otro.
//
// Criterio: en vez de intentar enumerar cada disfraz, se enumera la ÚNICA
// forma aceptada. Un comando sensible (borrar, git que publica/reescribe/
// descarta, ejecutar código arbitrario, red) solo pasa si está escrito en su
// forma canónica y solo -- exactamente la forma que la política sí cubre con
// "ask", así el usuario ve el pedido de permiso. Cualquier otra forma
// (encadenada, con prefijo, con ruta absoluta, con comillas en el nombre,
// dentro de $(...), con opciones de git antes del subcomando) se bloquea con
// un mensaje que dice cómo correrlo bien. La decisión allow/ask/deny sigue
// siendo de permission-policy.json; esto solo garantiza que la política vea
// el comando real.
//
// Límite honesto: un agente con permiso de edición puede escribir un script
// a un archivo y correrlo; eso no se detecta acá. La verificación que no se
// puede falsificar localmente vive en CI (ver docs/security-model.md).

const CANONICAL_GIT_SUBS = [
  'push', 'reset', 'clean', 'checkout', 'restore', 'commit', 'switch',
  'rebase', 'merge', 'revert', 'cherry-pick', 'update-ref', 'filter-branch',
  'filter-repo', 'gc', 'branch -d', 'branch -D', 'worktree remove',
  'worktree prune', 'stash drop', 'stash clear', 'reflog expire',
  'reflog delete',
];

// Opciones de git que pueden ir ANTES del subcomando (detección amplia).
const GIT_OPT = String.raw`(?:\s+(?:-C\s+\S+|-c\s+\S+|--(?:git-dir|work-tree|namespace|exec-path)(?:=\S+|\s+\S+)|--[a-z][\w-]*))*`;
const GIT_SUB_BROAD = String.raw`(?:push|reset|clean|checkout|restore|commit|switch|rebase|merge|revert|cherry-pick|update-ref|filter-branch|filter-repo|gc|branch\s+(?:-[a-zA-Z]*[dD]\b|--delete\b)|worktree\s+(?:remove|prune)|stash\s+(?:drop|clear)|reflog\s+(?:expire|delete))`;
const GIT_SENSITIVE = new RegExp(String.raw`^git${GIT_OPT}\s+${GIT_SUB_BROAD}(?:\s|$)`);

const GIT_CANONICAL = new RegExp(
  String.raw`^git (?:-C \S+ )?(?:${CANONICAL_GIT_SUBS.map((s) => s.replace(/[-]/g, '\\-')).join('|')})(?: |$)`,
);

const DELETE_RE = /^(?:rm|rmdir|unlink|shred|srm|trash)(?:\s|$)/;
const INTERP_RE = [
  /^(?:bash|sh|zsh|dash|ksh|fish)\s+(?:-[a-zA-Z]*c\b|-s\b|-\s*$)/,
  /^(?:bash|sh|zsh|dash|ksh|fish)\s*(?:-\s*)?<</,
  /^eval(?:\s|$)/,
  /^(?:python[\d.]*|pypy\S*)\s+(?:-[a-zA-Z]*c\b|-\s|-$)/,
  /^(?:python[\d.]*|pypy\S*|node|ruby|perl)\s*(?:-\s*)?<</,
  /^(?:node|nodejs|deno|bun)\s+(?:-e\b|-p\b|--eval\b|--print\b|-$|eval\b)/,
  /^(?:ruby|perl)\s+(?:-[a-zA-Z]*e\b|-$)/,
  /^php\s+-r\b/,
  /^osascript\b/,
];
const NET_RE = /^(?:curl|wget|nc|ncat|netcat|socat|scp|sftp|rsync|ssh|telnet|ftp)(?:\s|$)/;

const CANONICAL_OTHER = [
  /^(?:rm|rmdir|unlink|shred)(?: |$)/,
  /^find /,
  /^(?:bash|sh|zsh) -c /,
  /^eval /,  // # lens:ok: regex que detecta eval, no lo ejecuta
  /^(?:python|python3) -c /,
  /^node (?:-e|-p|--eval) /,
  /^(?:ruby|perl) -e /,
  /^php -r /,
  /^(?:curl|wget|nc|ncat|netcat|socat|scp|sftp|rsync|ssh|telnet|ftp) /,
];

// Identidad y evidencia las ponen el runtime y los scripts, nunca el agente.
// TEAMDB_CLAIM_* fija el hash/exit code que sella un receipt: con eso se
// "aprobaba" un candidato distinto al staged (caso real en ucadigital).
// SKALLING_VERIFY_WAIVER aprueba sin tests: es decisión humana, no del agente.
const IDENTITY_VARS = /\b(?:SKALLING_RUNTIME_AGENT|SKALLING_RUNTIME_SESSION|SKALLING_WORKFLOW_CHECK|TEAMDB_ACTOR|SKALLING_REVIEW_AGENT|SKALLING_VERIFY_WAIVER|TEAMDB_CLAIM_(?:TREE_HASH|EXIT_CODE|COMMAND|OUTPUT_SUMMARY))\b/;
// `env -i` / `env --ignore-environment` borra la identidad que puso el
// runtime sin nombrar ninguna variable (auditoría v0.12.0: el sello salía a
// nombre de otro agente).
const SCRUB_ENV = /(?:^|[\s;&|(`])env\s+(?:-[a-zA-Z]*i\b|--ignore-environment\b|-\s)/;


// Cuerpos de heredoc: con delimitador entre comillas (<<'EOF') son texto
// inerte; sin comillas solo se ejecuta lo que esté en $(...) o `...`. El
// caso típico es el mensaje de commit (`git commit -m "$(cat <<'EOF' ...`),
// cuyo texto puede mencionar "git push" o "rm" sin ejecutarlos.
function removeHeredocBodies(cmd) {
  return cmd.replace(
    /<<(-?)[ \t]*(['"]?)([A-Za-z_]\w*)\2([^\n]*)\n([\s\S]*?)\n[ \t]*\3[ \t]*(?=\n|$)/g,
    (_m, _dash, quote, delim, rest, body) => {
      if (quote) return `<<${delim}${rest}`;
      const subs = [];
      body.replace(/\$\(([^()]*)\)|`([^`]*)`/g, (_s, a, b) => { subs.push(a ?? b); return ''; });
      return `<<${delim}${rest}${subs.map((s) => ` ; ${s}`).join('')}`;
    },
  );
}

// Enmascara (con espacios, conservando el largo) lo que no puede actuar como
// separador de comandos: contenido entre comillas simples, texto entre
// comillas dobles salvo las sustituciones $(...)/`...` (esas SÍ se
// ejecutan), caracteres escapados y redirecciones tipo 2>&1.
function maskInert(text) {
  let out = '';
  let i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    if (c === '\\' && i + 1 < n) { out += '  '; i += 2; continue; }
    if (c === '$' && text[i + 1] === "'") {
      const j = text.indexOf("'", i + 2);
      const end = j === -1 ? n - 1 : j;
      out += ' '.repeat(end - i + 1); i = end + 1; continue;
    }
    if (c === "'") {
      const j = text.indexOf("'", i + 1);
      const end = j === -1 ? n - 1 : j;
      out += ' '.repeat(end - i + 1); i = end + 1; continue;
    }
    if (c === '"') {
      out += ' '; i += 1;
      while (i < n && text[i] !== '"') {
        if (text[i] === '\\' && i + 1 < n) { out += '  '; i += 2; continue; }
        if (text[i] === '$' && text[i + 1] === '(') {
          let depth = 0;
          const start = i;
          while (i < n) {
            if (text[i] === '(') depth += 1;
            else if (text[i] === ')') { depth -= 1; if (depth === 0) { i += 1; break; } }
            i += 1;
          }
          out += text.slice(start, i); continue;
        }
        if (text[i] === '`') {
          const j = text.indexOf('`', i + 1);
          const end = j === -1 ? n - 1 : j;
          out += text.slice(i, end + 1); i = end + 1; continue;
        }
        out += ' '; i += 1;
      }
      if (i < n) { out += ' '; i += 1; }
      continue;
    }
    out += c; i += 1;
  }
  return out.replace(/\d*>&\d*-?|&>>?|<&\d*/g, (m) => ' '.repeat(m.length));
}

const OPERATOR_RE = /&&|\|\||;;|;|\|&|\||&|\n|\$\(|`|<\(|>\(|\(|\)/g;

function splitSegments(cmd) {
  const base = removeHeredocBodies(cmd);
  const masked = maskInert(base);
  const segments = [];
  const operators = [];
  let last = 0;
  let indirect = false;
  let m;
  OPERATOR_RE.lastIndex = 0;
  while ((m = OPERATOR_RE.exec(masked)) !== null) {
    const raw = base.slice(last, m.index);
    // $(...) o `...` en la posición del nombre de comando: el comando real
    // se decide en tiempo de ejecución ("$(echo git) push").
    if ((m[0] === '$(' || m[0] === '`') && masked.slice(last, m.index).trim() === '') {
      const prevOp = operators[operators.length - 1];
      if (m[0] === '$(' || prevOp !== '`') indirect = true;
    }
    if (raw.trim()) segments.push(raw.trim());
    operators.push(m[0]);
    last = m.index + m[0].length;
  }
  const tail = base.slice(last);
  if (tail.trim()) segments.push(tail.trim());
  return { segments, operators, indirect };
}

function dequote(s) {
  return s.replace(/\$'([^']*)'/g, '$1').replace(/['"\\]/g, '');
}

// Quita todo lo que puede ir antes del comando real sin cambiar lo que se
// ejecuta: asignaciones VAR=x, command/env/exec/nohup/timeout..., palabras
// clave de shell (do/then/{ ...), y la ruta del ejecutable (/usr/bin/git).
function normalize(seg) {
  let s = dequote(seg).trim();
  for (;;) {
    const prev = s;
    s = s.replace(/^(?:do|then|else|elif|if|while|until|!|\{|time)\s+/, '');
    s = s.replace(/^[A-Za-z_][A-Za-z0-9_]*=\S*\s+/, '');
    s = s.replace(/^(?:command|builtin|exec|nohup|noglob)\s+/, '');
    s = s.replace(/^env(?:\s+(?:-[a-zA-Z]+\b(?:\s+[A-Za-z_]\w*\b(?!=))?|[A-Za-z_]\w*=\S*))*\s+/, '');
    s = s.replace(/^(?:timeout|gtimeout)(?:\s+-\S+)*\s+\S+\s+/, '');
    s = s.replace(/^nice(?:\s+-n\s+\S+|\s+-\d+)?\s+/, '');
    s = s.replace(/^stdbuf(?:\s+-\S+)+\s+/, '');
    s = s.replace(/^sudo(?:\s+-\S+)*\s+/, '');
    s = s.replace(/^\S*\/(?=[^\s/]+(?:\s|$))/, '');
    if (s === prev) break;
  }
  return s;
}

// find es sensible solo si borra o ejecuta algo sensible; xargs, según lo
// que ejecute.
function xargsInner(s) {
  const tokens = s.split(/\s+/).slice(1);
  const withArg = new Set(['-I', '-P', '-n', '-L', '-s', '-d', '-E', '-a', '-i']);
  let i = 0;
  while (i < tokens.length && tokens[i].startsWith('-')) {
    i += withArg.has(tokens[i]) ? 2 : 1;
  }
  return tokens.slice(i).join(' ');
}

function classify(norm) {
  if (!norm) return null;
  if (/^\$/.test(norm)) return 'indirecto';
  // El motor de borrado de TeamDB solo corre en su forma de terminal, con el
  // SQL a la vista del permiso; mandarle JSON por stdin esquivaba la aprobación.
  if (/teamdb-destructive\.py/.test(norm)) return 'borrado-db';
  if (GIT_SENSITIVE.test(norm)) return 'git';
  if (DELETE_RE.test(norm)) return 'borrado';
  if (/^find\b/.test(norm)) {
    if (/\s-delete\b/.test(norm)) return 'borrado';
    const ex = norm.match(/\s-(?:exec|execdir|ok|okdir)\s+(.*)$/);
    if (ex && classify(normalize(ex[1]))) return 'borrado';
    return null;
  }
  if (/^xargs\b/.test(norm)) return classify(normalize(xargsInner(norm))) ? 'ejecucion' : null;
  if (INTERP_RE.some((re) => re.test(norm))) return 'ejecucion';
  if (NET_RE.test(norm)) return 'red';
  return null;
}

function isCanonical(raw, kind) {
  if (kind === 'git') return GIT_CANONICAL.test(raw);
  if (kind === 'indirecto') return false;
  if (kind === 'borrado-db') return /^python3 \S*teamdb-destructive\.py (?:preview|apply) /.test(raw);
  return CANONICAL_OTHER.some((re) => re.test(raw));
}

// Devuelve null si el comando puede seguir a la política de permisos, o
// { kind, segment } si hay que bloquearlo.
export function guardCommand(command) {
  const cmd = command || '';
  const { segments, operators, indirect } = splitSegments(cmd);
  const findings = segments
    .map((raw) => ({ raw, norm: normalize(raw) }))
    .map((s) => ({ ...s, kind: classify(s.norm) }))
    .filter((s) => s.kind);
  if (indirect) return { kind: 'indirecto', segment: cmd.trim() };
  if (findings.length === 0) return null;

  if (segments.length === 1) {
    const [f] = findings;
    return isCanonical(f.raw, f.kind) ? null : { kind: f.kind, segment: f.norm };
  }
  // Única forma compuesta aceptada: `cd <dir> && git <sensible>`, que la
  // política cubre explícitamente con "ask".
  if (segments.length === 2 && operators.length === 1 && ['&&', ';', '\n'].includes(operators[0])
      && /^cd (?:\S+|"[^"]+"|'[^']+')$/.test(segments[0]) && findings.length === 1
      && findings[0].raw === segments[1] && findings[0].kind === 'git'
      && GIT_CANONICAL.test(segments[1])) {
    return null;
  }
  // Un comando sensible en forma directa cuyos únicos "otros segmentos"
  // salen de sustituciones dentro de sus propios argumentos
  // (`git commit -m "$(cat <<'EOF' ...)"`): nada corre encadenado a nivel
  // superior, y el patrón del permiso se evalúa contra el comando sensible.
  if (findings.length === 1 && findings[0].raw === segments[0]
      && isCanonical(findings[0].raw, findings[0].kind)
      && onlyArgumentSubstitutions(operators)) {
    return null;
  }
  return { kind: findings[0].kind, segment: findings[0].norm };
}

function onlyArgumentSubstitutions(operators) {
  let depth = 0;
  let inBacktick = false;
  for (const op of operators) {
    if (op === '`') { inBacktick = !inBacktick; continue; }
    if (op === '$(' || op === '(' || op === '<(' || op === '>(') {
      if (depth === 0 && !inBacktick && op !== '$(') return false;
      depth += 1;
      continue;
    }
    if (op === ')') { depth -= 1; if (depth < 0) return false; continue; }
    if (depth === 0 && !inBacktick) return false;
  }
  return depth === 0 && !inBacktick;
}

export function guardMessage(finding) {
  return `Comando sensible (${finding.kind}) disfrazado o encadenado: \`${finding.segment}\`. `
    + 'Correlo solo, en su forma directa (ej. `git push ...`, `rm ...`, `curl ...`, `bash -c ...`), '
    + 'para que el permiso lo pueda preguntar. Los argumentos normales están bien (`git push origin v2`, '
    + '`git commit -F msg.txt`); lo único permitido antes es un `cd <dir>` (mejor: usá el parámetro workdir). '
    + 'No se puede encadenar con otros comandos (&& ; | salto de línea) ni esconder en $(...), '
    + 'prefijos (command, env, VAR=...), rutas absolutas o comillas en el nombre del comando.';
}

// Compatibilidad con la versión anterior del plugin.
export function blocksChainedSensitiveGit(command) {
  return guardCommand(command) !== null;
}

export function normalizeAgent(agent) {
  return String(agent || '').trim().toLowerCase();
}

// La identidad la pone el runtime (OpenCode sabe qué agente corre cada
// sesión); un comando que intente fijarla o cambiarla es una falsificación.
// Agentes sin permiso de edición. Alex orquesta; Luz, Jhon, Pol, Sol y Jes
// revisan, verifican, planifican o investigan. Su bash permite `echo *`,
// `cat *`, scripts de TeamDB, etc.; sin este chequeo podían escribir código
// igual por la terminal (el caso real: Alex con el editor bloqueado cambió 3
// archivos con `sed -i` y `python3 <<PY open(path, 'w')`).
const NO_EDIT_AGENTS = new Set(['alex', 'luz', 'jhon', 'pol', 'sol', 'jes']);
const SCRATCH_TARGET = /^(?:\/dev\/(?:null|stdout|stderr|fd\/\d+)|\/tmp\/|\/private\/tmp\/|\/var\/folders\/|\$\{?TMPDIR\}?\/)/;
const IN_PLACE = /^(?:sed|gsed) (?:.* )?(?:-i|--in-place)|^(?:perl|ruby) (?:.* )?-[a-zA-Z]*i/;
const FILE_WRITERS = /^(?:cp|mv|install|ln|rsync|touch|truncate|dd|patch|tee|mkdir|rmdir|chmod|chown)(?: |$)|^git (?:apply|am|mv|rm)(?: |$)/;
const INLINE_CODE = /^(?:python3?|node|ruby|perl|php|deno|bun) (?:-c|-e|-p|--eval|-r) /;
const WRITE_CALL = /\bopen\([^)]*['"][wax+]|\.write_(?:text|bytes)\(|\bshutil\.|\bos\.(?:remove|unlink|rename|replace|makedirs|mkdir|rmdir|symlink)\(|\bfs\.(?:promises\.)?(?:write|append|unlink|rename|rm|mkdir|copy|cp|symlink|truncate)\w*\(|\.(?:unlink|rename|touch|mkdir)\(|\bFile\.(?:write|open)|\.(?:write|append)File\w*\(|\.(?:rm|unlink|rename|copyFile|cp|mkdir|symlink|truncate)Sync\(|\bfile_put_contents\(|\bunlink\(/;

function readWord(text, i) {
  while (i < text.length && /\s/.test(text[i])) i += 1;
  let word = '';
  while (i < text.length && !/[\s;&|<>()]/.test(text[i])) {
    const q = text[i];
    if (q === '"' || q === "'") {
      const j = text.indexOf(q, i + 1);
      const end = j === -1 ? text.length : j;
      word += text.slice(i + 1, end); i = end + 1; continue;
    }
    word += text[i]; i += 1;
  }
  return word;
}

function noEditMessage(agent, detail) {
  if (agent === 'alex') {
    return `Alex no implementa (${detail}). No es una herramienta que falte: es a propósito. `
      + 'Pasale el cambio a Teo con la herramienta de subagente (agent: teo) y después a Jhon para verificar. '
      + 'Si todavía no clasificaste el pedido, corré primero skalling-route.sh classify --record.';
  }
  return `${agent} no edita archivos del proyecto (${detail}). Si necesitás guardar una salida, usá /tmp/...; `
    + 'si hay que cambiar código, devolvé el hallazgo para que lo haga Teo.';
}

export function writeViolation(command, agent) {
  const who = normalizeAgent(agent);
  if (!NO_EDIT_AGENTS.has(who)) return null;
  const base = removeHeredocBodies(command || '');
  const masked = maskInert(base);
  const targets = [];
  const redirect = /(?<![<>&])>>?\|?(?!&)/g;
  let m;
  while ((m = redirect.exec(masked)) !== null) targets.push(readWord(base, m.index + m[0].length));
  const both = /&>>?/g;
  while ((m = both.exec(base)) !== null) targets.push(readWord(base, m.index + m[0].length));
  for (const seg of splitSegments(base).segments) {
    const norm = normalize(seg);
    if (IN_PLACE.test(norm)) return noEditMessage(who, `edición en el lugar: \`${norm}\``);
    if (INLINE_CODE.test(norm) && WRITE_CALL.test(seg)) return noEditMessage(who, `código inline que escribe archivos: \`${norm}\``);
    if (FILE_WRITERS.test(norm)) {
      const args = norm.split(/\s+/).slice(1).filter((a) => a && !a.startsWith('-'));
      const dest = /^(?:cp|mv|install|ln|rsync)(?: |$)/.test(norm) ? args.slice(-1) : args;
      if (dest.length === 0 || dest.some((a) => !SCRATCH_TARGET.test(a))) {
        return noEditMessage(who, `\`${norm}\` modifica archivos`);
      }
    }
  }
  const bad = targets.find((t) => !t || !SCRATCH_TARGET.test(t));
  if (bad === undefined) return null;
  return noEditMessage(who, `redirección hacia \`${bad || '?'}\``);
}

export function hookBypassViolation(command) {
  // Se mira el comando con las comillas enmascaradas: un mensaje de commit
  // que menciona "--no-verify" no es saltarse nada.
  const masked = maskInert(removeHeredocBodies(command || ''));
  const bypass = (/(?:^|\s)--no-verify\b/.test(masked) && /\bgit\b/.test(masked))
    || /\bgit\s+(?:-C\s+\S+\s+)?commit\b[^\n;&|]*\s-[a-zA-Z]*n[a-zA-Z]*(?=\s|$)/.test(masked)
    || /\bcore\.hooksPath\b|\bHUSKY=0\b/.test(masked);
  if (!bypass) return null;
  return 'Los hooks de git no se saltan (--no-verify, -n, core.hooksPath): son el gate que exige la '
    + 'verificación de Jhon o Luz sobre el candidato exacto. Si el commit o el push se bloquea, falta esa '
    + 'verificación: pedísela a Jhon (o a Luz con skalling-review.sh). Tampoco se le sugiere al usuario saltarlos.';
}

export function identityViolation(command) {
  if (IDENTITY_VARS.test(command || '') || SCRUB_ENV.test(maskInert(removeHeredocBodies(command || '')))) {
    return 'La identidad del agente la pone el runtime de OpenCode, no el comando: '
      + 'no se puede fijar SKALLING_RUNTIME_AGENT, TEAMDB_ACTOR, SKALLING_REVIEW_AGENT, SKALLING_VERIFY_WAIVER ni TEAMDB_CLAIM_* '
      + '(el hash y el resultado que sella un receipt los calcula el script sobre lo staged).';
  }
  return null;
}

// ─── Núcleo compartido por OpenCode v1 y v2 ──────────────────────────────────
// Cada versión entrega los mismos datos con otra forma; los adaptadores de
// abajo los traducen a { tool, agent, sessionID, input } y aplican la
// decisión a su manera (v1: throw; v2: reemplazar el comando, porque un error
// lanzado desde un hook de la v2 no se convierte en un rechazo limpio).
const SHELL_TOOLS = new Set(['bash', 'shell']);
const SUBAGENT_TOOLS = new Set(['task', 'subagent']);
const EDIT_TOOLS = new Set(['edit', 'write', 'patch', 'multiedit', 'apply_patch']);
const WORKFLOW_TOOL = 'skalling_workflow';
// Alex delega solo al equipo. Los agentes nativos de OpenCode (general,
// build, explore...) editan sin pasar por Teo ni por la clasificación.
const TEAM = new Set(['pol', 'sol', 'teo', 'jhon', 'luz', 'pau', 'jes']);

function parseState(output) {
  // v1: string. v2: { output?, content } con content string o partes de texto.
  const content = output?.content;
  const text = typeof output === 'string' ? output
    : (output?.output ?? output?.stdout ?? (typeof content === 'string' ? content : content?.[0]?.text)
      ?? JSON.stringify(output ?? ''));
  try {
    const state = JSON.parse(typeof text === 'string' ? text : JSON.stringify(text));
    return state && typeof state.id === 'string' && typeof state.state === 'string' ? state : null;
  } catch { return null; }
}

export function createCore() {
  // Último workflow que vio cada sesión de Alex (start/status/complete de
  // skalling_workflow). Delegar implementación exige que ESE workflow esté
  // en implementation_ready: la autorización es del pedido vigente, no un
  // "esta sesión clasificó alguna vez" (auditoría externa v0.12.0 #1).
  const workflows = new Map();

  function decide({ tool, agent, sessionID, input }) {
    const who = normalizeAgent(agent);
    if (SHELL_TOOLS.has(tool)) {
      const command = String(input?.command || '');
      const identity = identityViolation(command) || hookBypassViolation(command);
      if (identity) return identity;
      if (/skalling-workflow\.py/.test(command)) {
        return 'Use skalling_workflow: identidad y evidencia provienen del runtime, no de --by ni de variables shell.';
      }
      const finding = guardCommand(command);
      if (finding) return guardMessage(finding);
      return writeViolation(command, who);
    }
    if (EDIT_TOOLS.has(tool) && NO_EDIT_AGENTS.has(who)) {
      return noEditMessage(who, `herramienta ${tool}`);
    }
    if (SUBAGENT_TOOLS.has(tool) && who === 'alex') {
      const target = normalizeAgent(input?.agent || input?.subagent_type);
      if (!TEAM.has(target)) {
        return `Alex delega solo al equipo (Pol, Sol, Teo, Jhon, Luz, Pau, Jes); "${target || '?'}" no es parte del flujo `
          + 'y podría editar sin clasificación ni verificación.';
      }
      // Pedido DIRIGIDO a otro rol ("Jhon verifica...", "Sos Jhon...") pero
      // enviado a otro agente: caso real en 2.0.18 (el trabajo de Jhon a Teo,
      // dos veces). Solo cuenta el rol con que EMPIEZA el pedido; mencionarlo
      // en medio ("Verificar los cambios de Teo" a Jhon) es legítimo. Los
      // roles los impone skalling_workflow; esto evita la vuelta perdida.
      const ROLE = '(alex|pol|sol|teo|jhon|luz|pau|jes)\\b';
      const addressed = String(input?.description || '').trim().toLowerCase().match(new RegExp('^' + ROLE))
        || String(input?.prompt || '').trim().toLowerCase()
          .match(new RegExp('^(?:sos|eres|you are|actuá como|actua como)\\s+' + ROLE));
      if (addressed && addressed[1] !== target) {
        const role = addressed[1][0].toUpperCase() + addressed[1].slice(1);
        return `El pedido está dirigido a ${role} pero lo mandás a ${target}: usá agent: "${role}" `
          + '(cada rol registra su propia acción en skalling_workflow).';
      }
      if (target === 'teo') {
        const current = workflows.get(sessionID);
        if (!current) {
          return 'Sin workflow no se delega implementación: skalling_workflow start (Alex) con riesgo, alcance, '
            + 'archivos, aceptación y reutilización. Una decisión pendiente se resuelve con el usuario antes.';
        }
        if (current.state !== 'implementation_ready') {
          return `El workflow ${current.id} está en ${current.state}, no en implementation_ready: Teo implementa `
            + 'cuando la ruta lo habilita (low: ya; medium: tras Sol ready; high: Pol → Sol). '
            + 'Si cambió (Jhon rechazó), consultá skalling_workflow status.';
        }
        const text = `${input?.prompt || ''} ${input?.description || ''}`;
        if (!text.includes(current.id)) {
          return `Incluí el id del workflow (${current.id}) en el pedido a Teo: la delegación queda atada a ese pedido.`;
        }
      }
    }
    return null;
  }

  function observe({ tool, agent, sessionID, output }) {
    if (tool !== WORKFLOW_TOOL || normalizeAgent(agent) !== 'alex') return;
    const state = parseState(output);
    if (state) workflows.set(sessionID, { id: state.id, state: state.state });
  }

  return { decide, observe, workflows };
}

// OpenCode v1: hooks devueltos por la función `server`. El agente de cada
// sesión llega en chat.params; tool.execute.before no lo trae.
export function createGuard(agentBySession = new Map(), core = createCore()) {
  const remember = async (input) => {
    if (input?.sessionID && input?.agent) agentBySession.set(input.sessionID, normalizeAgent(input.agent));
  };
  return {
    'chat.params': remember,
    'chat.message': remember,
    'shell.env': async (input, output) => {
      const agent = agentBySession.get(input?.sessionID);
      // Sin agente conocido se falla cerrado: los helpers de TeamDB no
      // aceptan una identidad declarada dentro de OpenCode.
      output.env.SKALLING_RUNTIME_AGENT = agent || UNATTRIBUTED_AGENT;
      if (input?.sessionID) output.env.SKALLING_RUNTIME_SESSION = String(input.sessionID);
    },
    'tool.execute.before': async (input, output) => {
      const agent = agentBySession.get(input.sessionID);
      const blocked = core.decide({ tool: input.tool, agent, sessionID: input.sessionID, input: output.args });
      if (blocked) throw new Error(blocked);
    },
    'tool.execute.after': async (input, output) => {
      core.observe({ tool: input.tool, agent: agentBySession.get(input.sessionID), sessionID: input.sessionID,
        input: input.args, output: output?.output });
    },
  };
}

const UNATTRIBUTED_AGENT = 'unattributed';

function blockedShell(message) {
  return `echo '${`BLOQUEADO por Skalling: ${message}`.replace(/'/g, "'\\''")}'`;
}

// OpenCode v2: setup registra hooks en ctx. execute.before ya trae el agente.
// Para bloquear, el comando se reemplaza por un echo con el motivo (lo ve el
// agente como salida); una herramienta que no es shell se redirige a ese
// mismo echo.
//
// Identidad: shell create.before NO trae sesión, llamada ni agente (API
// documentada de 2.0.x: command, cwd, timeout, shell, env). La única
// correlación posible es el texto del comando aprobado un instante antes.
// Eso es ambiguo cuando dos sesiones corren el mismo comando: en vez de
// adivinar (y darle a Jhon la identidad de Teo), se marca "ambiguous" y los
// helpers de TeamDB fallan cerrado (teamdb_runtime_actor lo rechaza). Las
// entradas vencen a los PENDING_TTL_MS: un comando aprobado que nunca llegó a
// ejecutarse (permiso denegado) no contamina uno posterior.
const AMBIGUOUS_AGENT = 'ambiguous';
// Entre execute.before (registro) y create.before (ejecución) puede estar el
// prompt de permiso del usuario: con 30 s, una aprobación lenta dejaba el
// comando SIN identidad y el script aceptaba la declarada (auditoría v0.12.0).
// Ahora la ventana es amplia y lo no atribuible falla cerrado.
const PENDING_TTL_MS = 15 * 60 * 1000;

export function createIdentityQueue(now = () => Date.now()) {
  const pending = new Map();
  const live = (command) => (pending.get(command) || []).filter((e) => now() - e.at < PENDING_TTL_MS);
  return {
    register(command, agent, session = '') {
      pending.set(command, [...live(command), { agent: normalizeAgent(agent), session: String(session || ''), at: now() }]);
    },
    // Un comando denegado nunca llega a create.before: execute.after retira
    // su entrada para que no vuelva ambigua una ejecución posterior.
    discard(command, agent, session = '') {
      const entries = live(command);
      const index = entries.findIndex((e) => e.agent === normalizeAgent(agent) && e.session === String(session || ''));
      if (index >= 0) entries.splice(index, 1);
      if (entries.length) pending.set(command, entries); else pending.delete(command);
    },
    take(command) {
      const entries = live(command);
      if (entries.length === 0) { pending.delete(command); return null; }
      const owners = new Set(entries.map((e) => `${e.agent}\u0000${e.session}`));
      // Con más de un agente/sesión esperando el mismo texto, el orden de
      // ejecución no dice cuál es cuál: todas las entradas vivas son ambiguas.
      const single = owners.size === 1;
      const first = single ? { agent: entries[0].agent, session: entries[0].session }
        : { agent: AMBIGUOUS_AGENT, session: '' };
      const rest = entries.slice(1).map((e) => (single ? e : { ...e, agent: AMBIGUOUS_AGENT, session: '' }));
      if (rest.length) pending.set(command, rest); else pending.delete(command);
      return first;
    },
  };
}

export async function setupGuardV2(ctx, core = createCore(), identities = createIdentityQueue()) {
  await ctx.tool.hook('execute.before', async (event) => {
    const blocked = core.decide({ tool: event.tool, agent: event.agent, sessionID: event.sessionID, input: event.input });
    if (blocked) {
      event.tool = 'shell';
      event.input = { command: blockedShell(blocked) };
      return;
    }
    if (SHELL_TOOLS.has(event.tool) && event.agent && typeof event.input?.command === 'string') {
      identities.register(event.input.command, event.agent, event.sessionID);
    }
  });
  await ctx.tool.hook('execute.after', async (event) => {
    if (SHELL_TOOLS.has(event.tool) && event.status !== 'completed' && typeof event.input?.command === 'string') {
      identities.discard(event.input.command, event.agent, event.sessionID);
    }
    core.observe({ tool: event.tool, agent: event.agent, sessionID: event.sessionID, input: event.input,
      output: event.status === 'completed' ? event.result : '' });
  });
  await ctx.shell.hook('create.before', async (event) => {
    // Sin registro previo (TTL vencido, comando que no vino de un agente)
    // se falla cerrado en vez de dejar que el script crea lo declarado.
    const owner = identities.take(event.command) || { agent: UNATTRIBUTED_AGENT, session: '' };
    event.env = { ...(event.env || {}), SKALLING_RUNTIME_AGENT: owner.agent };
    if (owner.session) event.env.SKALLING_RUNTIME_SESSION = owner.session;
  });
}
