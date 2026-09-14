-- v0.11.4: agrega coverage_runs (historial de corridas de skalling-coverage.sh).
-- Aditiva: percent NULL significa que el comando corrio pero el formato de
-- salida no se reconocio, nunca que se invento un numero.
CREATE TABLE IF NOT EXISTS coverage_runs (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  command TEXT NOT NULL,
  format TEXT,
  percent REAL,
  lines_covered INTEGER,
  lines_total INTEGER,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_coverage_runs_ts ON coverage_runs(ts DESC);

UPDATE schema_meta SET value = '0.11.4' WHERE key = 'version';
