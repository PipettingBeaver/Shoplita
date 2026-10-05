#!/usr/bin/env bash
# Serves this folder so Tampermonkey can install/update from:
#   http://127.0.0.1:8791/Shoplita.dev.user.js
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m http.server "${1:-8791}" --bind 127.0.0.1
