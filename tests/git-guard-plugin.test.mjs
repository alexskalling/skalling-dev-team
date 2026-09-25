import test from 'node:test';
import assert from 'node:assert/strict';
import { blocksChainedSensitiveGit } from '../plugins/lib/git-guard.mjs';

test('bloquea git push/reset/etc. encadenado detrás de un prefijo permitido', () => {
  assert.equal(blocksChainedSensitiveGit('git add . && git push'), true);
  assert.equal(blocksChainedSensitiveGit('git add -A && git commit -m "x" && git push'), true);
  assert.equal(blocksChainedSensitiveGit('echo listo; git push origin main'), true);
  assert.equal(blocksChainedSensitiveGit('npm test | git reset --hard'), true);
  assert.equal(blocksChainedSensitiveGit('git add . && git -C /tmp/wt push'), true);
  assert.equal(blocksChainedSensitiveGit('cat file.txt && git branch -D old-branch'), true);
  assert.equal(blocksChainedSensitiveGit('ls && git worktree remove /tmp/wt'), true);
});

test('no bloquea git push/reset/etc. como comando único, sin encadenar', () => {
  assert.equal(blocksChainedSensitiveGit('git push'), false);
  assert.equal(blocksChainedSensitiveGit('git push origin main'), false);
  assert.equal(blocksChainedSensitiveGit('git -C /tmp/wt push'), false);
  assert.equal(blocksChainedSensitiveGit('git branch -D old-branch'), false);
});

test('no bloquea comandos encadenados sin ningún git sensible de por medio', () => {
  assert.equal(blocksChainedSensitiveGit('git add . && git status'), false);
  assert.equal(blocksChainedSensitiveGit('ls && cat file.txt'), false);
  assert.equal(blocksChainedSensitiveGit('git diff && git log'), false);
});

test('no confunde un "git push" mencionado dentro de un string literal con una invocación real', () => {
  assert.equal(blocksChainedSensitiveGit('echo "recordar: git push" && ls'), false);
  assert.equal(blocksChainedSensitiveGit('git commit -m "no hacer git push todavia"'), false);
});

test('command vacío o undefined no rompe, simplemente no bloquea', () => {
  assert.equal(blocksChainedSensitiveGit(''), false);
  assert.equal(blocksChainedSensitiveGit(undefined), false);
});
