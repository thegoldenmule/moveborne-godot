#!/usr/bin/env bash
# Sync a game's web build into ./site (the nginx payload). Keeps snap-site-host reusable:
# the build is NOT committed here — you point this at whichever game's build output you want
# to host, then `docker build` / `snapctl byosnap publish`.
#
# Usage:
#   ./sync-build.sh                 # defaults to ../web-dist (this repo's Moveborne web build)
#   ./sync-build.sh /path/to/build  # any other game's web export dir
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$SCRIPT_DIR/../web-dist}"
DEST="$SCRIPT_DIR/site"

if [[ ! -f "$SRC/index.html" ]]; then
  echo "✗ no index.html in '$SRC' — is that a built web export?" >&2
  exit 1
fi

echo "──▶ syncing $SRC → site/"
# Clear the old payload but keep the tracked drop-target files.
find "$DEST" -mindepth 1 ! -name .gitkeep ! -name .gitignore -delete
# Copy the build in (contents of SRC, not the dir itself).
cp -R "$SRC"/. "$DEST"/
echo "──── site/ ready ($(find "$DEST" -type f | wc -l | tr -d ' ') files) ────"
echo "  build:  docker build -t site-host ."
echo "  run:    docker run --rm -p 8080:8080 site-host  →  http://localhost:8080/v1/byosnap-site-host/"
