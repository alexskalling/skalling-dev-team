"""Resolve a real project before initialization; never treat HOME as a project."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def resolve_project(value, *, codegraph=False, allow_empty=False):
    path = Path(value).expanduser().resolve()
    home = Path.home().resolve()
    config = Path(os.environ.get('SKALLING_OPENCODE_DIR', home/'.config/opencode')).resolve()
    forbidden = {Path(path.anchor), home, config, home/'.opencode'}
    if not path.is_dir() or path in forbidden:
        raise ValueError(f'No es una carpeta de proyecto válida: {path}')
    result = subprocess.run(['git', '-C', str(path), 'rev-parse', '--show-toplevel'],
                            capture_output=True, text=True)
    if result.returncode == 0:
        path = Path(result.stdout.strip()).resolve()
    if path in forbidden:
        raise ValueError(f'La raíz resuelta no es un proyecto válido: {path}')
    markers = ('.git', 'package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml',
               'composer.json', 'pom.xml', 'build.gradle', 'Makefile', 'CMakeLists.txt',
               'README.md', '.opencode/project.yaml')
    if not allow_empty and not any((path/name).exists() for name in markers):
        raise ValueError(f'No hay evidencia de proyecto en {path}; selecciona su raíz o inicializa su repositorio Git.')
    if codegraph:
        for temporary in {Path('/tmp').resolve(), Path('/var/tmp').resolve(), Path(tempfile.gettempdir()).resolve()}:
            if path == temporary or temporary in path.parents:
                raise ValueError('CodeGraph no se inicializa en carpetas temporales; usa un proyecto bajo tu carpeta personal.')
    return path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', nargs='?', default='.')
    parser.add_argument('--codegraph', action='store_true')
    parser.add_argument('--allow-empty', action='store_true')
    args = parser.parse_args()
    try:
        print(resolve_project(args.project, codegraph=args.codegraph, allow_empty=args.allow_empty))
    except (ValueError, OSError) as error:
        sys.exit(f'ERROR: {error}')
