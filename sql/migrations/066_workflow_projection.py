"""Index operational workflow fields without duplicating their source of truth.

Idempotent and transactional: an interrupted migration is safe to retry.
Existing JSON, evidence and durable memory remain untouched.
"""
from contextlib import closing
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from skalling_db import connect


def migrate(path):
    with closing(connect(path)) as db:
        db.execute('BEGIN IMMEDIATE')
        try:
            columns = {r[1] for r in db.execute("PRAGMA table_xinfo(agent_workflows)")}
            for column, kind, key in (
                ('workflow_state', 'TEXT', 'state'), ('project_directory', 'TEXT', 'project_directory'),
                ('start_session', 'TEXT', 'start_session'), ('state_revision', 'REAL', 'updated_at')):
                if column not in columns:
                    db.execute(f"ALTER TABLE agent_workflows ADD COLUMN {column} {kind} "
                               f"GENERATED ALWAYS AS (json_extract(body,'$.{key}')) VIRTUAL")
            db.execute('CREATE INDEX IF NOT EXISTS idx_workflow_project_session '
                       'ON agent_workflows(project_directory,start_session,workflow_state)')
            db.execute('CREATE INDEX IF NOT EXISTS idx_workflow_project_state '
                       'ON agent_workflows(project_directory,workflow_state)')
            db.execute('CREATE INDEX IF NOT EXISTS idx_workflow_event_session '
                       'ON agent_workflow_events(request_id,session,ts)')
            db.commit()
        except BaseException:
            db.rollback()
            raise


if __name__ == '__main__':
    migrate(sys.argv[1])
