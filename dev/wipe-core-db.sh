#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

db="${1:-data/recorder-core.db}"

echo "[wipe-core-db] repo: $repo_root"
echo "[wipe-core-db] db: $db"

# Best-effort: stop a running recorder_core so the wipe takes effect immediately.
if command -v pkill >/dev/null 2>&1; then
  pkill -f "recorder_core" 2>/dev/null || true
fi

rm -f "$db" "$db-wal" "$db-shm" "$db-journal" 2>/dev/null || true

echo "[wipe-core-db] done."
echo "[wipe-core-db] next: cargo run -p recorder_core -- --listen 127.0.0.1:17600"
