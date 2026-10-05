#!/usr/bin/env bash
# Dev loop: keeps Shoplita.user.js / Shoplita.dev.user.js in sync and serves
# them on http://127.0.0.1:8791 so Tampermonkey can update in one click.
# Override the port with bash tools/dev.sh 9000
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-8791}"
export PORT

bash tools/sync.sh &
SYNC_PID=$!
trap 'kill "$SYNC_PID" 2>/dev/null || true' EXIT

printf 'Install/update http://127.0.0.1:%s/Shoplita.dev.user.js in Tampermonkey, then use "Check for updates".\n' "$PORT"
python3 -m http.server "$PORT" --bind 127.0.0.1
