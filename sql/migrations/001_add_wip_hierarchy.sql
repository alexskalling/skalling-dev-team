-- v0.7.1: Jerarquía en work_in_progress
-- Agrega type (plan|feature|task) y parent_id (auto-referencia)

ALTER TABLE work_in_progress ADD COLUMN type TEXT;
ALTER TABLE work_in_progress ADD COLUMN parent_id INTEGER REFERENCES work_in_progress(id);
ALTER TABLE work_in_progress ADD COLUMN description TEXT;

CREATE INDEX idx_wip_parent ON work_in_progress(parent_id);
CREATE INDEX idx_wip_type ON work_in_progress(type);

-- Update existing rows: hazlos tasks sin padre
UPDATE work_in_progress SET type='task' WHERE type IS NULL;
