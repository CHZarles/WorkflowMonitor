#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LISTEN="${1:-127.0.0.1:17600}"
DB="${2:-./data/recorder-core.db}"

export RUST_LOG="${RUST_LOG:-recorder_core=info,tower_http=info}"

echo "[run-core] repo: $ROOT"
echo "[run-core] listen: $LISTEN"
echo "[run-core] db: $DB"

exec ~/.cargo/bin/cargo run -p recorder_core -- --listen "$LISTEN" --db "$DB"

