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

const IDENTITY_VARS = /\b(?:SKALLING_RUNTIME_AGENT|TEAMDB_ACTOR|SKALLING_REVIEW_AGENT)\b/;
const IDENTITY_SCRIPTS = /(?:^|[\s;&|(`'"/])(?:bash\s+)?(\S*(?:teamdb-claim|teamdb-seal-receipt|skalling-review)\.sh)\b/;

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
  if (segments.length === 2 && operators.length === 1 && operators[0] === '&&'
      && /^cd \S+$/.test(segments[0]) && findings.length === 1
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
    + 'para que el permiso lo pueda preguntar. No se puede encadenar con && ; | ni esconder en $(...), '
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
// Roles sin permiso de edición (revisan, prueban, planifican, investigan).
// Su lista blanca de bash incluye `echo *`, `cat *`, etc.; sin este chequeo,
// `echo x > src/app.ts` o `cat a | tee b` escribirían archivos igual.
const READ_ONLY_AGENTS = new Set(['luz', 'jhon', 'pol', 'sol', 'jes']);
const SCRATCH_TARGET = /^(?:\/dev\/(?:null|stdout|stderr|fd\/\d+)|\/tmp\/|\/private\/tmp\/|\/var\/folders\/|\$\{?TMPDIR\}?\/)/;

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

export function writeViolation(command, agent) {
  if (!READ_ONLY_AGENTS.has(normalizeAgent(agent))) return null;
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
    if (/^tee(?: |$)/.test(norm)) {
      norm.split(/\s+/).slice(1).filter((a) => a && !a.startsWith('-')).forEach((a) => targets.push(a));
    }
  }
  const bad = targets.find((t) => !t || !SCRATCH_TARGET.test(t));
  if (bad === undefined) return null;
  return `${normalizeAgent(agent)} no edita archivos del proyecto: la redirección/tee hacia \`${bad || '?'}\` `
    + 'está bloqueada. Si necesitás guardar una salida, usá /tmp/...; si hay que cambiar código, '
    + 'devolvé el hallazgo para que lo haga el agente que implementa.';
}

export function identityViolation(command) {
  if (IDENTITY_VARS.test(command || '')) {
    return 'La identidad del agente la pone el runtime de OpenCode, no el comando: '
      + 'no se puede fijar SKALLING_RUNTIME_AGENT, TEAMDB_ACTOR ni SKALLING_REVIEW_AGENT.';
  }
  return null;
}

// Antepone SKALLING_RUNTIME_AGENT=<agente> a cada invocación de los scripts
// que registran quién aprueba/sella, en la posición exacta de la invocación
// (así funciona también dentro de un `cd x && ...`).
export function injectRuntimeAgent(command, agent) {
  const who = normalizeAgent(agent);
  if (!who || !/^[a-z][a-z0-9_-]*$/.test(who)) return command;
  if (!IDENTITY_SCRIPTS.test(command || '')) return command;
  return command.replace(
    /(^|&&\s*|;\s*|\|\|\s*|\n\s*)((?:bash\s+)?\S*(?:teamdb-claim|teamdb-seal-receipt|skalling-review)\.sh\b)/g,
    (_m, sep, invocation) => `${sep}SKALLING_RUNTIME_AGENT=${who} ${invocation}`,
  );
}

// Hooks del plugin. OpenCode informa en cada llamada al modelo qué agente
// corre en cada sesión (los subagentes tienen su propia sesión): ese dato no
// lo puede falsificar el agente, a diferencia de un --by=jhon en el comando.
// Vive acá y no en plugins/skalling-git-guard.js porque OpenCode trata cada
// export de un archivo de plugin como un plugin.
export function createGuard(agentBySession = new Map()) {
  const remember = async (input) => {
    if (input?.sessionID && input?.agent) agentBySession.set(input.sessionID, normalizeAgent(input.agent));
  };
  return {
    'chat.params': remember,
    'chat.message': remember,
    'shell.env': async (input, output) => {
      const agent = agentBySession.get(input?.sessionID);
      if (agent) output.env.SKALLING_RUNTIME_AGENT = agent;
    },
    'tool.execute.before': async (input, output) => {
      if (input.tool !== 'bash') return;
      const command = output.args.command || '';
      const identity = identityViolation(command);
      if (identity) throw new Error(identity);
      const finding = guardCommand(command);
      if (finding) throw new Error(guardMessage(finding));
      const agent = agentBySession.get(input.sessionID);
      const write = writeViolation(command, agent);
      if (write) throw new Error(write);
      if (agent) output.args.command = injectRuntimeAgent(command, agent);
    },
  };
}
