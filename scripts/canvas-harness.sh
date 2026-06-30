#!/bin/bash
# Opens the standalone Mermaid canvas harness in the default browser. Requires mermaid.min.js fetched
# (scripts/fetch-mermaid.sh). The harness loads the same canvas.css/canvas.js as production.
# Pass --editor to open in diagram-editor mode (header + code pane + AI chat); default is the bare canvas.
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
res="$repo_root/Sources/BlockInputKitWebKit/Resources"
if [ ! -f "$res/mermaid.min.js" ]; then
  echo "mermaid.min.js not found — run scripts/fetch-mermaid.sh first." >&2
  exit 1
fi
query=""
if [ "${1:-}" = "--editor" ]; then
  query="?editor"
fi
# Serve over HTTP so the ?editor query string works (open file://…?editor is treated as a literal path) and
# relative script/style loads resolve cleanly. Pick a port, start a background static server, open, and keep
# it alive until the user quits with Ctrl-C.
port=8745
( cd "$res" && python3 -m http.server "$port" >/dev/null 2>&1 ) &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null' EXIT
sleep 0.5
open "http://localhost:$port/canvas-harness.html$query"
echo "Serving the canvas harness at http://localhost:$port/canvas-harness.html$query (Ctrl-C to stop)…"
wait "$server_pid"
