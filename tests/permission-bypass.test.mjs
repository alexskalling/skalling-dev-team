// Regresión de la auditoría 2026-09-27: combinaciones de guard + política de
// permisos que dejaban correr sin pedir permiso cosas que debían preguntar.
//
// La decisión se calcula como OpenCode: gana la ÚLTIMA regla que coincide y
// `*` acepta cualquier texto (espacios y `/` incluidos). H0 está copiado del
// binario de OpenCode 2.0.18 (Wildcard): si una versión nueva cambia esa
// semántica, este test tiene que actualizarse junto con la política.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createCore } from '../plugins/lib/git-guard.mjs';

const policy = JSON.parse(fs.readFileSync(new URL('../data/permission-policy.json', import.meta.url)));
const ROLES = Object.keys(policy.profiles).filter((name) => name !== 'project');

function H0(text, pattern) {
  let s = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
  if (s.endsWith(' .*')) s = s.slice(0, -3) + '( .*)?';
  return new RegExp('^' + s + '$', 's').test(text);
}

function policyDecision(role, command) {
  const profile = policy.profiles[role];
  let decision = 'ask';
  for (const pattern of profile.bash_patterns) {
    if (H0(command, pattern)) decision = profile.overrides[pattern] ?? policy.rules[pattern];
  }
  return decision;
}

function decision(role, command) {
  const core = createCore();
  const blocked = core.decide({ tool: 'bash', agent: role.toLowerCase(), sessionID: 's', input: { command } });
  return blocked ? 'block' : policyDecision(role, command);
}

// Ninguno puede quedar en "allow" para ningún rol.
const MUST_NOT_RUN_SILENTLY = [
  // Comodín antes de la ruta del helper: cualquier script con una ruta de helper como argumento.
  'bash /tmp/x.sh /.opencode/scripts/teamdb-read.sh',
  '/tmp/x.sh /.opencode/scripts/teamdb-read.sh',
  'bash /tmp/x.sh ~/.config/opencode/scripts/teamdb-status.sh',
  'bash /tmp/x.sh x/.config/opencode/scripts/teamdb-context.sh',
  // El `*` del home en los patrones anclados no puede tragarse otro script.
  'bash /Users/x.sh /Users/a/.config/opencode/scripts/teamdb-read.sh',
  '/home/x.sh /home/a/.config/opencode/scripts/teamdb-read.sh',
  'bash tests/ok.sh /tmp/y.test.sh',
  'python3 /tmp/x.py x/teamdb-destructive.py preview y',
  // Path traversal en el permiso de tests.
  'bash tests/../../tmp/y.test.sh',
  // Un allow laxo no pisa una regla crítica.
  'git -C . push --force origin diff',
  'git branch -v -D main',
  'git branch -a -f main HEAD~3',
  // Canales hacia afuera y opciones que ejecutan programas.
  'git fetch https://example.invalid/x',
  'git fetch --prune https://example.invalid/x',
  'git fetch --upload-pack=/tmp/x.sh origin',
  'GIT_SSH_COMMAND=/tmp/x.sh git fetch origin',
  'rg --pre /tmp/x.sh foo src',
  'sort --compress-program=/tmp/x.sh big.txt',
  "sed -n '1e id' README.md",
  "sed 's/a/b/e' README.md",
  'sed -f /tmp/script.sed README.md',
  // Credenciales.
  'grep -r . .env',
  'grep -rn KEY .env.production',
  'cat .e*v',
  'grep -r TOKEN .',
  'head -c 100 ~/.ssh/id_rsa',
  'git show HEAD:.env',
  'cp .env /tmp/copia',
  'npm test .env',
  'cat config/secrets.yml',
  'head certs/server.key',
  // Identidad armada en tiempo de ejecución.
  'v=SKALLING_RUNTIME; export ${v}_AGENT=jhon',
];

test('ninguna evasión conocida corre sin pedir permiso', () => {
  const leaks = [];
  for (const role of [...ROLES]) {
    for (const command of MUST_NOT_RUN_SILENTLY) {
      if (decision(role, command) === 'allow') leaks.push(`${role}: ${command}`);
    }
  }
  assert.deepEqual(leaks, []);
});

test('los roles sin edición no escriben archivos ni en /tmp', () => {
  for (const role of ['Alex', 'Jes', 'Pol', 'Sol', 'Jhon', 'Luz']) {
    for (const command of ["echo 'x' > /tmp/x.sh", 'sort -o src/a.ts /tmp/in', 'git diff --output=src/a.ts',
      "sed -n 'w src/a.ts' README.md", 'find . -name x -fprint src/a.ts', 'tree -o src/a.ts']) {
      assert.notEqual(decision(role, command), 'allow', `${role}: ${command}`);
    }
  }
});

const MUST_STAY_ALLOWED = {
  Alex: ['bash .opencode/scripts/teamdb-read.sh decisions', 'bash /Users/ana/.config/opencode/scripts/teamdb-read.sh x',
    'bash /home/ana/.config/opencode/scripts/teamdb-status.sh', 'bash ~/.config/opencode/scripts/skalling-route.sh classify --record',
    'git status', 'git -C /p diff', 'git fetch origin', 'git fetch origin main', 'git stash list', 'git branch -v',
    'git branch -a', 'rg foo src', 'grep -rn foo src/', "sed -n '10,20p' README.md", 'git log --oneline -5'],
  Jes: ['bash .opencode/scripts/teamdb-search.sh auth', 'cat README.md', 'git log --oneline -5'],
  Sol: ['bash .opencode/scripts/teamdb-plan.sh show x', 'bash ~/.config/opencode/scripts/teamdb-context.sh x'],
  Teo: ['bash tests/a.test.sh', 'npm test', 'npm run build', "sed -i 's/a/b/' src/x.js", 'git add src/a.js',
    'bash .opencode/scripts/teamdb-claim.sh x'],
  Jhon: ['bash tests/a.test.sh', 'bash .opencode/scripts/skalling-review.sh --lens risk'],
  Pau: ['bash .opencode/scripts/teamdb-memory.sh add decision x', 'bash ~/.config/opencode/scripts/teamdb-dump.sh'],
};

test('los comandos legítimos de cada rol siguen sin pedir permiso', () => {
  for (const [role, commands] of Object.entries(MUST_STAY_ALLOWED)) {
    for (const command of commands) assert.equal(decision(role, command), 'allow', `${role}: ${command}`);
  }
});

// Único `*` permitido antes del nombre del programa: el segmento del home en
// la ruta de un helper global (el guard bloquea que ese `*` se trague otro
// script: una ruta de helper solo vale como programa, no como argumento).
const HOME_HELPER = /^(?:bash |python3 )?\/(?:Users|home|c\/Users)\/\*\/\.config\/opencode\/scripts\/[\w.-]+(?: [\w-]+)*(?: \*)?$/;

test('ningún allow tiene un comodín antes de la ruta del programa', () => {
  const bad = [];
  for (const [role, profile] of Object.entries(policy.profiles)) {
    for (const pattern of profile.bash_patterns) {
      const value = profile.overrides[pattern] ?? policy.rules[pattern];
      if (value !== 'allow' || HOME_HELPER.test(pattern)) continue;
      if (pattern.startsWith('*') || /^\S+ \*\//.test(pattern) || pattern.includes('*/')) bad.push(`${role}: ${pattern}`);
    }
  }
  assert.deepEqual(bad, []);
});
