"""Read-only Git checks for sharing a Skalling bundle without runtime state.

Reports paths and attributes only. Reads .gitattributes, never TeamDB or source
contents. Does not stage files, edit rules, or certify absence of secrets.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

PUBLIC = ('.opencode/project.yaml', '.opencode/agents/Alex.md')
PRIVATE = ('.opencode/context/team.db', '.opencode/context/team.db-shm',
           '.opencode/context/team.db-wal', '.opencode/context/.locks/probe',
           '.skalling-backups/probe', '.opencode/scripts/__pycache__/probe.py')


def verify(project):
    def git(*args, accepted=(0,)):
        run = subprocess.run(['git', '-C', str(project), *args], capture_output=True,
                             text=True, timeout=15, env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})
        if run.returncode not in accepted:
            raise ValueError('Git no pudo comprobar ' + args[0] + ': ' + run.stderr.strip())
        return run

    root = Path(git('rev-parse', '--show-toplevel').stdout.strip())
    project = root
    checks = []

    def check(name, passed, detail):
        checks.append({'check': name, 'passed': bool(passed), 'detail': detail})

    for name in PUBLIC + PRIVATE:
        ignored = git('check-ignore', '--no-index', '-q', '--', name, accepted=(0, 1)).returncode == 0
        private = name in PRIVATE
        check(name, ignored == private and (private or (root/name).is_file()),
              'ignorado' if ignored else 'no ignorado')
    tracked = git('ls-files', '-z', '--', '.opencode/context/', '.skalling-backups/',
                  '.opencode/**/__pycache__/**').stdout.split('\0')
    tracked = [name for name in tracked if name]
    check('estado privado rastreado', not tracked, tracked)
    exposed = git('ls-files', '--others', '--exclude-standard', '-z', '--', '.opencode/context/').stdout
    check('contexto privado no rastreado', not exposed, [name for name in exposed.split('\0') if name])
    attributes = git('check-attr', '-z', 'merge', '--', 'db/teamdb/team.dump.sql', 'AGENTS.md').stdout.split('\0')
    for i in range(0, len(attributes)-1, 3):
        name, _, value = attributes[i:i+3]
        check('merge: ' + name, value == 'union', value)
    attr_file = root/'.gitattributes'
    declarations = {' '.join(line.split()) for line in attr_file.read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith('#')} if attr_file.is_file() else set()
    required = {'db/teamdb/team.dump.sql merge=union', '/AGENTS.md merge=union'}
    check('atributos compartidos', required.issubset(declarations),
          'reglas declaradas en .gitattributes del proyecto, además de sus valores efectivos')
    check('AGENTS.md existe', (root/'AGENTS.md').is_file(), 'instrucciones compartidas')
    return {'passed': all(item['passed'] for item in checks), 'checks': checks,
            'dump_exists': (root/'db/teamdb/team.dump.sql').is_file(),
            'scope': 'Reglas efectivas de Git y exposición del estado local. No revisa secretos del contenido, '
                     'historial remoto ni autoriza versionar todo el bundle. Un dump ausente no es un fallo.'}


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('Uso: skalling-privacy-check.py <raíz del proyecto>')
        report = verify(Path(sys.argv[1]).resolve())
        print(json.dumps(report, ensure_ascii=False, indent=2))
        sys.exit(0 if report['passed'] else 1)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit('ERROR: privacidad sin verificar: ' + str(error))
