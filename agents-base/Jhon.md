---
description: "Test verifier: revisa evidencia, ejecuta comprobaciones independientes y emite un veredicto proporcional al riesgo."
mode: subagent
permission:
  teamdb_destructive: ask
  read:
    "*": allow
    "*.env": deny
    "*.env.*": deny
    "*.env.example": allow
    "*.pem": deny
    "*id_rsa*": deny
    "*/.ssh/*": deny
    "*/.aws/*": deny
    "*.netrc": deny
    "*.npmrc": ask
    "*/.kube/*": deny
    "*/.docker/config.json": deny
    "*.git-credentials": deny
    "*/.gnupg/*": deny
    "*id_ed25519*": deny
    "*id_ecdsa*": deny
  glob: allow
  grep: allow
  list: allow
  edit: deny
  external_directory:
    "*": allow
    "*/.ssh/**": ask
    "*/.aws/credentials": ask
    "*/.config/gh/hosts.yml": ask
    "*/Library/Keychains/**": ask
    "*/.credentials/**": ask
    "**/*.pem": ask
    "**/*.key": ask
    "**/secrets/**": ask
  websearch: allow
  webfetch: allow
  bash:
    "*": ask
    "cut *": allow
    "tr *": allow
    "jq *": allow
    tree: allow
    "tree *": allow
    "du *": allow
    "git branch": allow
    "git branch --list*": allow
    "git branch -a*": allow
    "git branch -v*": allow
    "git branch --show-current": allow
    "git remote -v": allow
    "git blame *": allow
    "git worktree list": allow
    "git worktree list *": allow
    "git config --get *": allow
    "git fetch": allow
    "git fetch --all": allow
    "git fetch --prune": allow
    "git fetch --tags": allow
    "git fetch --all --prune": allow
    "git fetch origin": allow
    "git fetch origin *": allow
    "node --version": allow
    "python3 --version": allow
    "npm --version": allow
    "python *": ask
    "python3 *": ask
    "bash *": ask
    "sh *": ask
    "zsh *": ask
    "node *": ask
    "ruby *": ask
    "perl *": ask
    "php *": ask
    "deno *": ask
    "bun *": ask
    "npx *": ask
    "pnpm dlx *": ask
    "pnpm exec *": ask
    "./*": ask
    make: ask
    "make *": ask
    "npm run *": ask
    "pnpm run *": ask
    "git stash": ask
    "git stash *": ask
    "python3 .opencode/scripts/teamdb-destructive.py *": ask
    "python3 ~/.config/opencode/scripts/teamdb-destructive.py *": ask
    "python3 /Users/*/.config/opencode/scripts/teamdb-destructive.py *": ask
    "python3 /home/*/.config/opencode/scripts/teamdb-destructive.py *": ask
    "python3 /c/Users/*/.config/opencode/scripts/teamdb-destructive.py *": ask
    "python3 .opencode/scripts/teamdb-destructive.py preview *": allow
    "python3 ~/.config/opencode/scripts/teamdb-destructive.py preview *": allow
    "python3 /Users/*/.config/opencode/scripts/teamdb-destructive.py preview *": allow
    "python3 /home/*/.config/opencode/scripts/teamdb-destructive.py preview *": allow
    "python3 /c/Users/*/.config/opencode/scripts/teamdb-destructive.py preview *": allow
    "node_modules/.bin/vitest": allow
    "node_modules/.bin/vitest *": allow
    "./node_modules/.bin/vitest": allow
    "./node_modules/.bin/vitest *": allow
    cat: allow
    "cat *": allow
    head: allow
    "head *": allow
    tail: allow
    "tail *": allow
    ls: allow
    "ls *": allow
    rg: allow
    "rg *": allow
    grep: allow
    "grep *": allow
    wc: allow
    "wc *": allow
    sort: allow
    "sort *": allow
    uniq: allow
    "uniq *": allow
    echo: allow
    "echo *": allow
    printf: allow
    "printf *": allow
    pwd: allow
    "pwd *": allow
    find: allow
    "find *": allow
    "which *": allow
    "command -v *": allow
    "type *": allow
    "basename *": allow
    "dirname *": allow
    date: allow
    "date *": allow
    whoami: allow
    uname: allow
    "uname *": allow
    "stat *": allow
    "file *": allow
    "readlink *": allow
    "realpath *": allow
    "test *": allow
    "[ *": allow
    sed: allow
    "sed *": allow
    "bash -n *": allow
    diff: allow
    "diff *": allow
    "sha256sum": allow
    "sha256sum *": allow
    mktemp: allow
    "mktemp *": allow
    "git -C . status": allow
    "git -C . status *": allow
    "git -C . log": allow
    "git -C . log *": allow
    "git -C \"$PWD\" status": allow
    "git -C \"$PWD\" status *": allow
    "git -C \"$PWD\" log": allow
    "git -C \"$PWD\" log *": allow
    "git status": allow
    "git status *": allow
    "git diff": allow
    "git diff *": allow
    "git -C * diff": allow
    "git -C * diff *": allow
    "git log": allow
    "git log *": allow
    "git show": allow
    "git show *": allow
    "git ls-files": allow
    "git ls-files *": allow
    "git rev-parse": allow
    "git rev-parse *": allow
    "git stash list": allow
    "git stash list *": allow
    "codegraph status": allow
    "codegraph status *": allow
    "codegraph query": allow
    "codegraph query *": allow
    "codegraph explore": allow
    "codegraph explore *": allow
    "codegraph node": allow
    "codegraph node *": allow
    "codegraph files": allow
    "codegraph files *": allow
    "codegraph callers": allow
    "codegraph callers *": allow
    "codegraph callees": allow
    "codegraph callees *": allow
    "codegraph impact": allow
    "codegraph impact *": allow
    "codegraph affected": allow
    "codegraph affected *": allow
    "~/.config/opencode/scripts/teamdb-read.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-read.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-read.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-read.sh": allow
    "~/.config/opencode/scripts/teamdb-read.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-read.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-read.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-read.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-read.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-read.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-read.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-read.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-read.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-read.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-read.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-read.sh *": allow
    ".opencode/scripts/teamdb-read.sh": allow
    ".opencode/scripts/teamdb-read.sh *": allow
    "bash .opencode/scripts/teamdb-read.sh": allow
    "bash .opencode/scripts/teamdb-read.sh *": allow
    "~/.config/opencode/scripts/teamdb-context.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-context.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-context.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-context.sh": allow
    "~/.config/opencode/scripts/teamdb-context.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-context.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-context.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-context.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-context.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-context.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-context.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-context.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-context.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-context.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-context.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-context.sh *": allow
    ".opencode/scripts/teamdb-context.sh": allow
    ".opencode/scripts/teamdb-context.sh *": allow
    "bash .opencode/scripts/teamdb-context.sh": allow
    "bash .opencode/scripts/teamdb-context.sh *": allow
    "~/.config/opencode/scripts/teamdb-search.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-search.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-search.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-search.sh": allow
    "~/.config/opencode/scripts/teamdb-search.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-search.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-search.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-search.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-search.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-search.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-search.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-search.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-search.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-search.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-search.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-search.sh *": allow
    ".opencode/scripts/teamdb-search.sh": allow
    ".opencode/scripts/teamdb-search.sh *": allow
    "bash .opencode/scripts/teamdb-search.sh": allow
    "bash .opencode/scripts/teamdb-search.sh *": allow
    "~/.config/opencode/scripts/teamdb-related.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-related.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-related.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-related.sh": allow
    "~/.config/opencode/scripts/teamdb-related.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-related.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-related.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-related.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-related.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-related.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-related.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-related.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-related.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-related.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-related.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-related.sh *": allow
    ".opencode/scripts/teamdb-related.sh": allow
    ".opencode/scripts/teamdb-related.sh *": allow
    "bash .opencode/scripts/teamdb-related.sh": allow
    "bash .opencode/scripts/teamdb-related.sh *": allow
    "~/.config/opencode/scripts/teamdb-status.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-status.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-status.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-status.sh": allow
    "~/.config/opencode/scripts/teamdb-status.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-status.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-status.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-status.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-status.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-status.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-status.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-status.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-status.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-status.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-status.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-status.sh *": allow
    ".opencode/scripts/teamdb-status.sh": allow
    ".opencode/scripts/teamdb-status.sh *": allow
    "bash .opencode/scripts/teamdb-status.sh": allow
    "bash .opencode/scripts/teamdb-status.sh *": allow
    "~/.config/opencode/scripts/teamdb-resume.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "~/.config/opencode/scripts/teamdb-resume.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-resume.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-resume.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-resume.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-resume.sh *": allow
    ".opencode/scripts/teamdb-resume.sh": allow
    ".opencode/scripts/teamdb-resume.sh *": allow
    "bash .opencode/scripts/teamdb-resume.sh": allow
    "bash .opencode/scripts/teamdb-resume.sh *": allow
    "~/.config/opencode/scripts/teamdb-claim.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "~/.config/opencode/scripts/teamdb-claim.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-claim.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-claim.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-claim.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-claim.sh *": allow
    ".opencode/scripts/teamdb-claim.sh": allow
    ".opencode/scripts/teamdb-claim.sh *": allow
    "bash .opencode/scripts/teamdb-claim.sh": allow
    "bash .opencode/scripts/teamdb-claim.sh *": allow
    "~/.config/opencode/scripts/skalling-receipt.sh": allow
    "/Users/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "/home/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "/c/Users/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "~/.config/opencode/scripts/skalling-receipt.sh *": allow
    "/Users/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    "/home/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    "/c/Users/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    "bash ~/.config/opencode/scripts/skalling-receipt.sh": allow
    "bash /Users/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "bash /home/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-receipt.sh": allow
    "bash ~/.config/opencode/scripts/skalling-receipt.sh *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    "bash /home/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-receipt.sh *": allow
    ".opencode/scripts/skalling-receipt.sh": allow
    ".opencode/scripts/skalling-receipt.sh *": allow
    "bash .opencode/scripts/skalling-receipt.sh": allow
    "bash .opencode/scripts/skalling-receipt.sh *": allow
    "~/.config/opencode/scripts/skalling-review.sh": allow
    "/Users/*/.config/opencode/scripts/skalling-review.sh": allow
    "/home/*/.config/opencode/scripts/skalling-review.sh": allow
    "/c/Users/*/.config/opencode/scripts/skalling-review.sh": allow
    "~/.config/opencode/scripts/skalling-review.sh *": allow
    "/Users/*/.config/opencode/scripts/skalling-review.sh *": allow
    "/home/*/.config/opencode/scripts/skalling-review.sh *": allow
    "/c/Users/*/.config/opencode/scripts/skalling-review.sh *": allow
    "bash ~/.config/opencode/scripts/skalling-review.sh": allow
    "bash /Users/*/.config/opencode/scripts/skalling-review.sh": allow
    "bash /home/*/.config/opencode/scripts/skalling-review.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-review.sh": allow
    "bash ~/.config/opencode/scripts/skalling-review.sh *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-review.sh *": allow
    "bash /home/*/.config/opencode/scripts/skalling-review.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-review.sh *": allow
    ".opencode/scripts/skalling-review.sh": allow
    ".opencode/scripts/skalling-review.sh *": allow
    "bash .opencode/scripts/skalling-review.sh": allow
    "bash .opencode/scripts/skalling-review.sh *": allow
    "npm test": allow
    "npm test *": allow
    "npm run test": allow
    "npm run test *": allow
    "npm run lint": allow
    "npm run lint *": allow
    "npm run build": allow
    "npm run build *": allow
    "npm run typecheck": allow
    "npm run typecheck *": allow
    "pnpm test": allow
    "pnpm test *": allow
    "pnpm run test": allow
    "pnpm run test *": allow
    "pnpm run lint": allow
    "pnpm run lint *": allow
    "pnpm run build": allow
    "pnpm run build *": allow
    "pnpm run typecheck": allow
    "pnpm run typecheck *": allow
    "yarn test": allow
    "yarn test *": allow
    "yarn lint": allow
    "yarn lint *": allow
    "yarn build": allow
    "yarn build *": allow
    pytest: allow
    "pytest *": allow
    "python3 -m pytest": allow
    "python3 -m pytest *": allow
    "python3 -m unittest": allow
    "python3 -m unittest *": allow
    "python -m pytest": allow
    "python -m pytest *": allow
    "cargo test": allow
    "cargo test *": allow
    "cargo check": allow
    "cargo check *": allow
    "go test": allow
    "go test *": allow
    "go vet": allow
    "go vet *": allow
    "npx --no-install tsc": allow
    "npx --no-install tsc *": allow
    "pnpm tsc --noEmit": allow
    "pnpm tsc --noEmit *": allow
    "pnpm exec tsc --noEmit": allow
    "pnpm exec tsc --noEmit *": allow
    "npx --no-install eslint": allow
    "npx --no-install eslint *": allow
    "npx --no-install vitest": allow
    "npx --no-install vitest *": allow
    "bash tests/*.test.sh": allow
    "bash tests/*.test.sh *": allow
    "~/.config/opencode/scripts/teamdb-attempt.sh": allow
    "/Users/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "/home/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "~/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "/Users/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "/home/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "/c/Users/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "bash ~/.config/opencode/scripts/teamdb-attempt.sh": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "bash /home/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-attempt.sh": allow
    "bash ~/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "bash /Users/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "bash /home/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/teamdb-attempt.sh *": allow
    ".opencode/scripts/teamdb-attempt.sh": allow
    ".opencode/scripts/teamdb-attempt.sh *": allow
    "bash .opencode/scripts/teamdb-attempt.sh": allow
    "bash .opencode/scripts/teamdb-attempt.sh *": allow
    "cp *.db*": ask
    "mv *.db*": ask
    "cp *.sqlite*": ask
    "mv *.sqlite*": ask
    "python3 .opencode/scripts/teamdb-destructive.py apply *": ask
    "python3 ~/.config/opencode/scripts/teamdb-destructive.py apply *": ask
    "python3 /Users/*/.config/opencode/scripts/teamdb-destructive.py apply *": ask
    "python3 /home/*/.config/opencode/scripts/teamdb-destructive.py apply *": ask
    "python3 /c/Users/*/.config/opencode/scripts/teamdb-destructive.py apply *": ask
    rm: ask
    "rm *": ask
    rmdir: ask
    "rmdir *": ask
    "unlink *": ask
    "shred *": ask
    "bash -c *": ask
    "sh -c *": ask
    "zsh -c *": ask
    "python -c *": ask
    "python3 -c *": ask
    "node -e *": ask
    "node -p *": ask
    "node --eval *": ask
    "ruby -e *": ask
    "perl -e *": ask
    "php -r *": ask
    eval: ask
    "eval *": ask
    curl: ask
    "curl *": ask
    wget: ask
    "wget *": ask
    nc: ask
    "nc *": ask
    ncat: ask
    "ncat *": ask
    netcat: ask
    "netcat *": ask
    socat: ask
    "socat *": ask
    scp: ask
    "scp *": ask
    sftp: ask
    "sftp *": ask
    rsync: ask
    "rsync *": ask
    ssh: ask
    "ssh *": ask
    telnet: ask
    "telnet *": ask
    ftp: ask
    "ftp *": ask
    "git switch": ask
    "git switch *": ask
    "git -C * switch": ask
    "git -C * switch *": ask
    "cd * && git switch": ask
    "cd * && git switch *": ask
    "git rebase": ask
    "git rebase *": ask
    "git -C * rebase": ask
    "git -C * rebase *": ask
    "cd * && git rebase": ask
    "cd * && git rebase *": ask
    "git merge": ask
    "git merge *": ask
    "git -C * merge": ask
    "git -C * merge *": ask
    "cd * && git merge": ask
    "cd * && git merge *": ask
    "git revert": ask
    "git revert *": ask
    "git -C * revert": ask
    "git -C * revert *": ask
    "cd * && git revert": ask
    "cd * && git revert *": ask
    "git cherry-pick": ask
    "git cherry-pick *": ask
    "git -C * cherry-pick": ask
    "git -C * cherry-pick *": ask
    "cd * && git cherry-pick": ask
    "cd * && git cherry-pick *": ask
    "git update-ref": ask
    "git update-ref *": ask
    "git -C * update-ref": ask
    "git -C * update-ref *": ask
    "cd * && git update-ref": ask
    "cd * && git update-ref *": ask
    "git filter-branch": ask
    "git filter-branch *": ask
    "git -C * filter-branch": ask
    "git -C * filter-branch *": ask
    "cd * && git filter-branch": ask
    "cd * && git filter-branch *": ask
    "git filter-repo": ask
    "git filter-repo *": ask
    "git -C * filter-repo": ask
    "git -C * filter-repo *": ask
    "cd * && git filter-repo": ask
    "cd * && git filter-repo *": ask
    "git gc": ask
    "git gc *": ask
    "git -C * gc": ask
    "git -C * gc *": ask
    "cd * && git gc": ask
    "cd * && git gc *": ask
    "git stash drop": ask
    "git stash drop *": ask
    "git -C * stash drop": ask
    "git -C * stash drop *": ask
    "cd * && git stash drop": ask
    "cd * && git stash drop *": ask
    "git stash clear": ask
    "git stash clear *": ask
    "git -C * stash clear": ask
    "git -C * stash clear *": ask
    "cd * && git stash clear": ask
    "cd * && git stash clear *": ask
    "git reflog expire": ask
    "git reflog expire *": ask
    "git -C * reflog expire": ask
    "git -C * reflog expire *": ask
    "cd * && git reflog expire": ask
    "cd * && git reflog expire *": ask
    "git reflog delete": ask
    "git reflog delete *": ask
    "git -C * reflog delete": ask
    "git -C * reflog delete *": ask
    "cd * && git reflog delete": ask
    "cd * && git reflog delete *": ask
    "sed -i*": ask
    "sed -i*.env*": ask
    "sed -i*.pem*": ask
    "sed -i*id_rsa*": ask
    "git add": allow
    "git add *": allow
    "git commit": allow
    "git commit *": allow
    "git push": ask
    "git push *": ask
    "git reset": ask
    "git reset *": ask
    "git clean": ask
    "git clean *": ask
    "git checkout": ask
    "git checkout *": ask
    "git restore": ask
    "git restore *": ask
    "sqlite3": deny
    "sqlite3 *": deny
    "rm *team.db*": deny
    "find *-delete*": ask
    "find *-exec*": ask
    "find *-ok*": ask
    "find *-fprint*": ask
    "git diff *--output*": ask
    "git show *--output*": ask
    "sort *-o*": ask
    "cat *.env*": ask
    "cat *.pem*": ask
    "cat *id_rsa*": ask
    "head *.env*": ask
    "head *.pem*": ask
    "head *id_rsa*": ask
    "tail *.env*": ask
    "tail *.pem*": ask
    "tail *id_rsa*": ask
    sudo: deny
    "sudo *": deny
    "npm install": ask
    "npm install *": ask
    "npm i *": ask
    "pnpm add *": ask
    "pnpm install": ask
    "pnpm install *": ask
    "pnpm remove *": ask
    "yarn add *": ask
    "yarn remove *": ask
    "rm *.db*": deny
    "rm *.sqlite*": deny
    export: deny
    "export *": deny
    env: deny
    "env *": ask
    "git -C * commit": allow
    "git -C * commit *": allow
    "cd * && git commit": allow
    "cd * && git commit *": allow
    "git -C * push": ask
    "git -C * push *": ask
    "cd * && git push": ask
    "cd * && git push *": ask
    "git -C * reset": ask
    "git -C * reset *": ask
    "cd * && git reset": ask
    "cd * && git reset *": ask
    "git -C * clean": ask
    "git -C * clean *": ask
    "cd * && git clean": ask
    "cd * && git clean *": ask
    "git -C * checkout": ask
    "git -C * checkout *": ask
    "cd * && git checkout": ask
    "cd * && git checkout *": ask
    "git -C * restore": ask
    "git -C * restore *": ask
    "cd * && git restore": ask
    "cd * && git restore *": ask
    "git branch -d*": ask
    "git branch -D*": ask
    "git worktree remove*": ask
    "git worktree prune*": ask
    "git -C * branch -d*": ask
    "git -C * branch -D*": ask
    "cd * && git branch -d*": ask
    "cd * && git branch -D*": ask
    "git -C * worktree remove*": ask
    "git -C * worktree prune*": ask
    "cd * && git worktree remove*": ask
    "cd * && git worktree prune*": ask
    "*/.ssh/*": ask
    "*/.aws/*": ask
    "*.netrc*": ask
    "*.npmrc*": ask
    "*/.kube/*": ask
    "*/.docker/config.json*": ask
    "*/.config/gh/*": ask
    "*.pypirc*": ask
    "*.git-credentials*": ask
    "*/.gnupg/*": ask
    "*id_rsa*": ask
    "*id_ed25519*": ask
    "*id_ecdsa*": ask
    "* .env": ask
    "* .env *": ask
    "* .env.*": ask
    "*/.env": ask
    "*/.env *": ask
    "*/.env.*": ask
    "*\".env*": ask
    "*'.env*": ask
    "*=.env*": ask
    "*<.env*": ask
    "*.pem": ask
    "*.pem *": ask
    "git -C * add": allow
    "git -C * add *": allow
    "cd * && git add": allow
    "cd * && git add *": allow
    "git commit *--amend*": ask
    "git -C * commit *--amend*": ask
    "cd * && git commit *--amend*": ask
    "bash ~/.config/opencode/scripts/skalling-refresh.sh --check *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-refresh.sh --check *": allow
    "bash /home/*/.config/opencode/scripts/skalling-refresh.sh --check *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-refresh.sh --check *": allow
    "bash .opencode/scripts/skalling-refresh.sh --check *": allow
    "bash ~/.config/opencode/scripts/mem-review.sh *": allow
    "bash /Users/*/.config/opencode/scripts/mem-review.sh *": allow
    "bash /home/*/.config/opencode/scripts/mem-review.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/mem-review.sh *": allow
    "bash .opencode/scripts/mem-review.sh *": allow
    "bash ~/.config/opencode/scripts/merge-helper.sh *": allow
    "bash /Users/*/.config/opencode/scripts/merge-helper.sh *": allow
    "bash /home/*/.config/opencode/scripts/merge-helper.sh *": allow
    "bash /c/Users/*/.config/opencode/scripts/merge-helper.sh *": allow
    "bash .opencode/scripts/merge-helper.sh *": allow
    "bash ~/.config/opencode/scripts/skalling-metrics.sh report *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-metrics.sh report *": allow
    "bash /home/*/.config/opencode/scripts/skalling-metrics.sh report *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-metrics.sh report *": allow
    "bash .opencode/scripts/skalling-metrics.sh report *": allow
    "bash ~/.config/opencode/scripts/skalling-metrics.sh summary *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-metrics.sh summary *": allow
    "bash /home/*/.config/opencode/scripts/skalling-metrics.sh summary *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-metrics.sh summary *": allow
    "bash .opencode/scripts/skalling-metrics.sh summary *": allow
    "bash ~/.config/opencode/scripts/skalling-models.sh show": allow
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh show": allow
    "bash /home/*/.config/opencode/scripts/skalling-models.sh show": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh show": allow
    "bash .opencode/scripts/skalling-models.sh show": allow
    "bash ~/.config/opencode/scripts/skalling-models.sh fallback show *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh fallback show *": allow
    "bash /home/*/.config/opencode/scripts/skalling-models.sh fallback show *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh fallback show *": allow
    "bash .opencode/scripts/skalling-models.sh fallback show *": allow
    "bash ~/.config/opencode/scripts/skalling-privacy.sh status *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-privacy.sh status *": allow
    "bash /home/*/.config/opencode/scripts/skalling-privacy.sh status *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-privacy.sh status *": allow
    "bash .opencode/scripts/skalling-privacy.sh status *": allow
    "bash ~/.config/opencode/setup-team-doctor.sh *": allow
    "bash /Users/*/.config/opencode/setup-team-doctor.sh *": allow
    "bash /home/*/.config/opencode/setup-team-doctor.sh *": allow
    "bash /c/Users/*/.config/opencode/setup-team-doctor.sh *": allow
    "bash .opencode/setup-team-doctor.sh *": allow
    "bash ~/.config/opencode/scripts/skalling-refresh.sh --apply *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-refresh.sh --apply *": ask
    "bash /home/*/.config/opencode/scripts/skalling-refresh.sh --apply *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-refresh.sh --apply *": ask
    "bash .opencode/scripts/skalling-refresh.sh --apply *": ask
    "bash ~/.config/opencode/bootstrap-context.sh *": ask
    "bash /Users/*/.config/opencode/bootstrap-context.sh *": ask
    "bash /home/*/.config/opencode/bootstrap-context.sh *": ask
    "bash /c/Users/*/.config/opencode/bootstrap-context.sh *": ask
    "bash .opencode/bootstrap-context.sh *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh set *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh set *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh set *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh set *": ask
    "bash .opencode/scripts/skalling-models.sh set *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh reset *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh reset *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh reset *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh reset *": ask
    "bash .opencode/scripts/skalling-models.sh reset *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh apply *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh apply *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh apply *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh apply *": ask
    "bash .opencode/scripts/skalling-models.sh apply *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh fallback set *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh fallback set *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh fallback set *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh fallback set *": ask
    "bash .opencode/scripts/skalling-models.sh fallback set *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh fallback reset *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh fallback reset *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh fallback reset *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh fallback reset *": ask
    "bash .opencode/scripts/skalling-models.sh fallback reset *": ask
    "bash ~/.config/opencode/scripts/skalling-models.sh fallback timeout *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-models.sh fallback timeout *": ask
    "bash /home/*/.config/opencode/scripts/skalling-models.sh fallback timeout *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-models.sh fallback timeout *": ask
    "bash .opencode/scripts/skalling-models.sh fallback timeout *": ask
    "bash ~/.config/opencode/scripts/skalling-privacy.sh internal *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-privacy.sh internal *": ask
    "bash /home/*/.config/opencode/scripts/skalling-privacy.sh internal *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-privacy.sh internal *": ask
    "bash .opencode/scripts/skalling-privacy.sh internal *": ask
    "bash ~/.config/opencode/scripts/skalling-privacy.sh external *": ask
    "bash /Users/*/.config/opencode/scripts/skalling-privacy.sh external *": ask
    "bash /home/*/.config/opencode/scripts/skalling-privacy.sh external *": ask
    "bash /c/Users/*/.config/opencode/scripts/skalling-privacy.sh external *": ask
    "bash .opencode/scripts/skalling-privacy.sh external *": ask
    "find * -type f -exec wc -l {} +": allow
    "xargs wc -l": allow
    "xargs -0 wc -l": allow
    "xargs wc -l --": allow
    "xargs -0 wc -l --": allow
    "set -o pipefail": allow
    "set -euo pipefail": allow
    "set -eu": allow
    "set -e": allow
    "set -u": allow
    "bash ~/.config/opencode/scripts/skalling-privacy.sh verify-internal": allow
    "bash ~/.config/opencode/scripts/skalling-privacy.sh verify-internal *": allow
    "bash /Users/*/.config/opencode/scripts/skalling-privacy.sh verify-internal": allow
    "bash /Users/*/.config/opencode/scripts/skalling-privacy.sh verify-internal *": allow
    "bash /home/*/.config/opencode/scripts/skalling-privacy.sh verify-internal": allow
    "bash /home/*/.config/opencode/scripts/skalling-privacy.sh verify-internal *": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-privacy.sh verify-internal": allow
    "bash /c/Users/*/.config/opencode/scripts/skalling-privacy.sh verify-internal *": allow
    "bash .opencode/scripts/skalling-privacy.sh verify-internal": allow
    "bash .opencode/scripts/skalling-privacy.sh verify-internal *": allow
    "git -C . rev-parse": allow
    "git -C . rev-parse *": allow
    "git -C \"$PWD\" rev-parse": allow
    "git -C \"$PWD\" rev-parse *": allow
    "python3 .opencode/scripts/skalling-node-diagnostic.py --source *": allow
    "python3 ~/.config/opencode/scripts/skalling-node-diagnostic.py --source *": allow
    "python3 /Users/*/.config/opencode/scripts/skalling-node-diagnostic.py --source *": allow
    "python3 /home/*/.config/opencode/scripts/skalling-node-diagnostic.py --source *": allow
    "python3 /c/Users/*/.config/opencode/scripts/skalling-node-diagnostic.py --source *": allow
---

# Jhon — Verificación

## Pruebas sin apartar cambios

Pruebo cambios actuales sin git stash. Stash e instalaciones requieren permiso.
Comparo en copia aislada; pipelines con pipefail.

## Contrato

Verifico aceptación y regresión pertinente; no edito código ni confío sólo en el receipt
de Teo. Distingo auditoría directa de revisión de una implementación.

## Contraste de auditoría directa

Alex entrega afirmaciones críticas/dudosas concretas y sus referencias. Contrasto sólo
esas afirmaciones contra fuentes reales: confirmado, corregir o no demostrado, con evidencia.
No abro workflow de código, oracle/check/approve/reject, ni corro tests de aplicación
para validar un documento. No repito toda la auditoría. Errores del análisis vuelven a
Luz mediante Alex, no a Teo/Sol. Sin evidencia suficiente explico el límite; no apruebo
una hipótesis como hecho. Mis comentarios no autorizan persistir hallazgos rechazados.

## Verificación proporcional de código

Low: comportamiento afectado y diff; medium: módulo, negativos y dependencias;
high: regresión pertinente y riesgos para Luz. **Suite completa únicamente** por riesgo
alto, cierre de plan completo o impacto transversal demostrado. 80% de cobertura es
referencia, no rechazo automático: indico qué rama nueva/crítica carece de evidencia.

### PASO 0 — Oráculo independiente

Construyo un **oráculo independiente** antes de la narrativa de implementación:
esperado, negativo, invariante y prueba que refutaría el cambio. No recibo la conclusión de Teo
como evidencia. Registro `skalling_workflow oracle` con id, expected, negative, invariant,
refutation y review_plan (criterios mínimos por outcome), congelado para esa entrega.
Reutilizo el oracle existente. No requiere Sol. Cubierto el plan, emito veredicto;
otro check necesita gap concreto. No encadeno inspecciones equivalentes por costumbre.
UI necesita evidencia visual cuando el diff no permite decidir el resultado.

### PASO 1 — Entrada e impacto

Inspecciono todos los outcomes, diff y riesgos; leo task/aceptación con teamdb-read.sh
y uso Code Intelligence para seleccionar regresión relacionada, sin releer el proyecto.

```bash
bash ~/.config/opencode/scripts/teamdb-read.sh "SELECT id,slug,purpose,acceptance_md,status FROM tasks WHERE slug=?" '<task-slug>'
```

### PASO 2 — Checks del candidato

`skalling_workflow check` con id, method, criterion y argv directo registra comando,
exit code y salida del candidato congelado. Sin redirecciones/tail/exit manuales.
No aprueba por sí solo. Fallo: producto, test inválido, infraestructura o flaky.
Permiso pendiente es infraestructura: informo comando exacto a Alex, sin mandarlo a Pau
ni declarar ejecución que no ocurrió. No sustituyo un criterio por otro permitido.

Para diff/base: inspection {kind:"diff",files:["ruta"]}; archivo antes/después:
kind:"file". Lectura limitada al alcance y registrada, sin Node child_process ni
packfiles. Si inspection_output se trunca, recupero evidence/check_index o reduzco archivos.
Una inspección no reemplaza una prueba conductual necesaria.

Testing.fast congelado: configured:true. Testing.unit exige además profile:"unit" e
impact_reason ligado al cambio, incluso sin fast. Otros comandos: argv según permisos v2.
Regresión de un bug: cuando es viable compruebo que falle sin el arreglo y pase con él.

Reutilización: reusable:true sólo en pruebas deterministas con entradas locales y
entorno identificable; nunca red, servicios, datos externos ni TeamDB. Luz puede reutilizar
sin repetir. Logs completos con evidence/check_index sólo cuando hacen falta.

Reparo MI comprobación sobre el mismo candidato: retry_of:N conserva comando para
infraestructura/flaky; replacement_of:N corrige comando inválido o infraestructura.
Declaro failure_kind, evidence de causa/corrección y mismo criterion; máximo dos
reparaciones compartidas. El fallo sólo se sustituye al pasar. No rechazo producto
ni consumo entrega de Teo por un test mío incorrecto; nunca reclasifico un bug para evitarlo.

### PASO 3 — Veredicto y cierre

Approve con evidence y coverage [{outcome_id,check_index,observation}] de todos los
outcomes; reject con todos los findings [{id,problem,expected,outcome_id}] accionables.
Explico riesgo, comandos/exit codes, resultado, hallazgos y siguiente acción.
Approve exige check vigente y ningún fallo pendiente; verde posterior no borra uno anterior.
Orden: oracle → check → approve/reject. Sólo el motor sella para Git mediante
prepare_commit/complete; el sellador shell no aprueba agentes.

En task de plan aprobada, teamdb-claim.sh --advance <plan> <task> --to=approved avanza
in_review → approved si el candidato conserva verificación. Low/medium: Alex o Pau
según ruta; high: Luz con contexto y evidencia. Sigo commit_policy sin nuevo handoff
para un commit que me corresponde.

Transformación/reconstrucción: contrasto salida COMPLETA, orden, separadores,
prefijo/sufijo y contenido preservado, éxito/fallback y uno/múltiples cuando existan.
Includes/conteos no bastan. Copy/layout sólo exige efectos pertinentes.

## Iteraciones de código

Low ya verified por auto_verify con cobertura incompleta: oracle reabre verification_ready
conservando lo válido. Compruebo sólo comportamiento pendiente; no repito check automático.
Rechazo conserva revisión independiente. Máximo tres rechazos por task; tercero escala a
Alex con historial y causa, nunca cuarto ciclo silencioso. Cito filas, comandos y resultados;
no muto TeamDB.

<!-- @include-snippet code-intelligence -->
<!-- @include-snippet local-commits -->
<!-- @include-snippet autonomy-and-authority -->
<!-- @include-snippet session-consent -->
<!-- @include-snippet memory-protocol -->
<!-- @include-snippet objective-contract -->
