// git-guard.mjs — cierra un hueco que data/permission-policy.json por sí
// solo no puede cerrar: el matcher de patrones de OpenCode compara el
// comando bash COMPLETO contra cada glob. Un patrón "allow" amplio como
// "git add *" matchea literalmente "git add . && git push", porque el "*"
// final absorbe cualquier cosa que siga -- incluido un "&& git push" pegado
// atrás. Encontrado por una revisión independiente: ningún patrón nuevo
// agregado a permission-policy.json esta noche podía cerrar esto, porque el
// bypass no usa NINGUNA de las formas de "git push" que se endurecieron
// (ni "git push" literal, ni "git -C <dir> push", ni "cd <dir> && git
// push") -- usa un prefijo DISTINTO que ya era "allow" desde antes.
//
// No intenta reimplementar ask/allow/deny (eso es responsabilidad de
// permission-policy.json). Sólo bloquea la forma ENCADENADA: si el
// comando real que se sella como git push/reset/etc. tiene que pasar por
// el permiso "ask" que ya existe, forzarlo a ir en su propio bash call.

const SENSITIVE_GIT_RE =
  /\bgit\s+(?:-C\s+\S+\s+)?(?:push|reset|clean|checkout|restore|commit|branch\s+-[dD]|worktree\s+(?:remove|prune))\b/;
const COMPOUND_OPERATOR_RE = /&&|\|\||;|\|/;

// Blanquea el contenido de strings entre comillas para no confundir un
// "git push" mencionado dentro de un string literal (ej. un mensaje de
// commit) con una invocación real, y para no partir en falso al buscar
// operadores compuestos que en realidad están dentro de una comilla.
function stripQuoted(command) {
  return command.replace(/'[^']*'|"(?:[^"\\]|\\.)*"/g, ' ');
}

export function blocksChainedSensitiveGit(command) {
  const stripped = stripQuoted(command || '');
  return COMPOUND_OPERATOR_RE.test(stripped) && SENSITIVE_GIT_RE.test(stripped);
}
