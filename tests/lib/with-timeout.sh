#!/usr/bin/env bash
# tests/lib/with-timeout.sh — timeout portable para los corredores de tests.
#
# macOS no trae `timeout` (coreutils) y bash 3.2 no tiene `wait -n`: se usa
# perl, presente en macOS, Linux y Git Bash. El comando corre en su propio
# process group para que, al vencer, se maten también sus hijos (un test
# colgado no deja procesos huérfanos). Sin timeout, una suite trabada deja la
# batería esperando para siempre sin decir cuál era.
#
# Uso: skalling_with_timeout <segundos> <comando> [args...]
# Sale con el código del comando, o 124 si venció el plazo (como coreutils).

skalling_with_timeout() {
  local secs="$1"; shift
  perl -e '
    my $t = shift;
    my $pid = fork();
    die "fork: $!\n" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec(@ARGV) or exit 127; }
    $SIG{ALRM} = sub {
      kill("TERM", -$pid); sleep 2; kill("KILL", -$pid);
      print STDERR "TIMEOUT: no terminó en ${t}s (proceso colgado o entorno bloqueado)\n";
      exit 124;
    };
    alarm $t;
    waitpid($pid, 0);
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$secs" "$@"
}
