from pathlib import Path
import json, os, shutil, sqlite3, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
base=Path(tempfile.mkdtemp(prefix='skalling-0153-lifecycle-'))
p=base/'project'; p.mkdir(); (p/'src').mkdir()
(p/'README.md').write_text('# Campaign service\n\nService for creating and sending campaigns with validated recipients.\n')
(p/'src/main.py').write_text('def create_campaign(name):\n    return {"name": name}\n')
(p/'pyproject.toml').write_text('[project]\nname = "campaign-service"\nversion = "1.0.0"\n')
bin_dir=base/'bin'; bin_dir.mkdir(); (bin_dir/'python3').symlink_to(shutil.which('python3'))
env=dict(os.environ,PATH=str(bin_dir)+':/usr/bin:/bin:/usr/sbin:/sbin',SKALLING_OPENCODE_DIR=str(base/'global'),AGENTS_SKILLS_DIR=str(base/'personal'),SKALLING_ROOT=str(base/'global'))
log=base/'lifecycle.log'
def run(args,expected=0):
    result=subprocess.run(args,env=env,text=True,capture_output=True,timeout=90,stdin=subprocess.DEVNULL)
    with log.open('a') as out: out.write('\nCOMMAND '+repr(args)+'\n'+result.stdout+result.stderr)
    if result.returncode!=expected: raise RuntimeError(f'{args}: exit={result.returncode}, expected={expected}; log={log}\n'+result.stderr[-2000:])
    return result.stdout
run(['git','-C',str(p),'init','-q'])
run(['bash',str(root/'install-global.sh')])
run(['bash',str(base/'global/bootstrap-context.sh'),'--target',str(p),'--install-project'])
run(['bash',str(base/'global/scripts/skalling-refresh.sh'),'--check',str(p)])
missing=p/'.opencode/skills/systematic-debugging/SKILL.md'; missing.unlink()
run(['bash',str(base/'global/scripts/skalling-refresh.sh'),'--check',str(p)],1)
run(['bash',str(base/'global/scripts/skalling-refresh.sh'),'--apply',str(p)])
assert missing.exists()
run(['bash',str(base/'global/scripts/teamdb-status.sh'),'',str(p)])
run(['bash',str(base/'global/scripts/teamdb-resume.sh'),str(p)])
run(['bash',str(base/'global/scripts/mem-review.sh'),'--target',str(p)])
run(['bash',str(base/'global/scripts/merge-helper.sh'),'--target',str(p)])
run(['bash',str(base/'global/scripts/skalling-metrics.sh'),'report',str(p)])
run(['bash',str(base/'global/scripts/skalling-privacy.sh'),'status',str(p)])
run(['bash',str(base/'global/scripts/update.sh'),'--local-only','--project',str(p),'--yes'])
run(['python3',str(base/'global/scripts/skalling-runtime.py'),'check','--root',str(base/'global'),'--target',str(p/'.opencode')])
run(['bash',str(base/'global/setup-team-doctor.sh'),'--project',str(p),'--strict'])
print('PASS: installed init → refresh check → missing skill detected → repair → status/resume/memory/merge/metrics/privacy → local update.')
print('Evidence:',log)
# The temporary log is retained as reproducible installation evidence.
