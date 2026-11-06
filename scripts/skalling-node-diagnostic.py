#!/usr/bin/env python3
"""Local Node diagnostics with resource permissions, never unrestricted eval.

Requires Node's network-aware permission model. This limits mistakes in trusted
verification code; it is not an isolation boundary against malicious programs.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    args = parser.parse_args()
    node = shutil.which('node')
    if not node:
        parser.error('Node no disponible; no se ejecutó el diagnóstico')
    # Do not let NODE_OPTIONS preloads or provider credentials enter the child.
    env = {k: v for k, v in os.environ.items() if k in
           {'PATH', 'LANG', 'LC_ALL', 'SYSTEMROOT', 'SystemRoot', 'WINDIR', 'TMPDIR', 'TEMP', 'TMP'}}
    probe = subprocess.run([node, '--permission', '-e',
                            "if(process.permission.has('net')!==false)process.exit(1)"],
                           env=env, capture_output=True, timeout=5)
    if probe.returncode:
        parser.error('Este Node no restringe red con --permission. Diagnóstico no ejecutado; '
                     'usar un runtime compatible o una prueba configurada que demuestre el criterio. '
                     'No se instala ni habilita un eval sin restricciones.')
    root = str(Path.cwd().resolve())
    argv = [node, '--permission', '--allow-fs-read=' + root, '-e', args.source]
    # Engine owns the timeout/process group; exec preserves cancellation.
    os.execve(node, argv, env)


if __name__ == '__main__':
    main()
