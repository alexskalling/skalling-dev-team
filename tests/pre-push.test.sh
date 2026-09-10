#!/usr/bin/env bash
# Behavioral replacement for legacy TTL/last-receipt/dump-freshness gates.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tests/git-close.test.py"
