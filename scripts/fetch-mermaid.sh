#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Pinned Mermaid release. The UMD build at dist/mermaid.min.js exposes a global `mermaid`
# that BlockInputWebContentRenderer loads into an offscreen WKWebView for offline rendering.
mermaid_version="${MERMAID_VERSION:-10.9.1}"
dest_dir="Sources/BlockInputKitWebKit/Resources"
dest="$dest_dir/mermaid.min.js"
url="https://cdn.jsdelivr.net/npm/mermaid@${mermaid_version}/dist/mermaid.min.js"

mkdir -p "$dest_dir"

if [ -f "$dest" ] && [ "${1:-}" != "--force" ]; then
  echo "mermaid.min.js already present ($dest). Use --force to re-download."
  exit 0
fi

echo "Fetching mermaid@${mermaid_version} -> $dest"
curl -fsSL "$url" -o "$dest"

# Sanity: the UMD bundle should be a few hundred KB+ and reference the mermaid global.
bytes=$(wc -c < "$dest" | tr -d ' ')
if [ "$bytes" -lt 100000 ]; then
  echo "Downloaded file looks too small ($bytes bytes); aborting." >&2
  rm -f "$dest"
  exit 1
fi

echo "Done: $dest ($bytes bytes). This file is gitignored; re-run this script after a fresh checkout."
