#!/usr/bin/env bash
# Generates the browser-loadable copies from the canonical Shoplita.txt:
#   Shoplita.user.js      clean installable copy (for sharing)
#   Shoplita.dev.user.js  dev copy with localhost @updateURL/@downloadURL
# Watches Shoplita.txt and rebuilds whenever it changes.
# Override the port with PORT=9000 bash tools/sync.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8791}"

build() {
  cp Shoplita.txt Shoplita.user.js
  sed "/^\/\/ @namespace/a\\
// @updateURL    http://127.0.0.1:${PORT}/Shoplita.dev.user.js\\
// @downloadURL  http://127.0.0.1:${PORT}/Shoplita.dev.user.js" Shoplita.txt > Shoplita.dev.user.js
}

build
printf 'initial build done: Shoplita.user.js + Shoplita.dev.user.js (port %s)\n' "$PORT"
while true; do
  if [ Shoplita.txt -nt Shoplita.user.js ] || [ Shoplita.txt -nt Shoplita.dev.user.js ]; then
    build
    printf 'synced %s\n' "$(date '+%H:%M:%S')"
  fi
  sleep 1
done
