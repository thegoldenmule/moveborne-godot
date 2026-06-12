#!/usr/bin/env bash
#
# build_web.sh — produce an optimized, static-host-ready web build of the
# Moveborne client in ./web-dist (committed; served as-is by AWS Amplify).
#
# Pipeline:
#   1. Export the "Web" preset in RELEASE mode (smaller, no debug template).
#   2. wasm-opt the engine wasm (strip debug/producers, -Oz).
#   3. Brotli-compress index.wasm + index.pck (the two huge files).
#   4. Assemble web-dist/: shipped assets + the vendored brotli decoder + a
#      fetch shim that decompresses the .br files in-browser (see
#      tools/web/mb_brotli_boot.js for the why).
#
# Why client-side decompression instead of `Content-Encoding: br`? Amplify
# treats Content-Encoding as a read-only header and rejects it, and CloudFront
# won't auto-compress application/wasm or files >10 MB. Client-side decode makes
# the build work on ANY dumb static host with zero header configuration.
#
# Usage:   tools/build_web.sh
# Env:     GODOT=/path/to/Godot   (defaults to the macOS app bundle)
#
# Requires: Godot 4.6 with web export templates, `brotli`, and `wasm-opt`
#           (brew install binaryen). wasm-opt is optional — skipped with a
#           warning if missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_DIR/game"
STAGE_DIR="$REPO_DIR/build/web"        # gitignored raw export staging
DIST_DIR="$REPO_DIR/web-dist"          # committed, Amplify-served output
VENDOR_DIR="$SCRIPT_DIR/web/vendor"

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

[[ -x "$GODOT" ]] || { echo "error: Godot not found at $GODOT (set GODOT=...)" >&2; exit 1; }
command -v brotli >/dev/null || { echo "error: brotli not found (brew install brotli)" >&2; exit 1; }

human() { # bytes -> MB string
  awk -v b="$1" 'BEGIN { printf "%.2f MB", b/1048576 }'
}
size() { stat -f%z "$1"; }

# --- 1. release export -------------------------------------------------------
echo "──▶ exporting Web preset (release) → build/web"
rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$STAGE_DIR/index.html" >/dev/null
[[ -f "$STAGE_DIR/index.wasm" && -f "$STAGE_DIR/index.pck" ]] \
  || { echo "error: export did not produce index.wasm/index.pck" >&2; exit 1; }

wasm_before="$(size "$STAGE_DIR/index.wasm")"

# --- 2. wasm-opt -------------------------------------------------------------
if command -v wasm-opt >/dev/null; then
  echo "──▶ wasm-opt (strip debug/producers, -Oz)"
  wasm-opt "$STAGE_DIR/index.wasm" -o "$STAGE_DIR/index.wasm.tmp" \
    --strip-debug --strip-producers -Oz -all --post-emscripten
  mv "$STAGE_DIR/index.wasm.tmp" "$STAGE_DIR/index.wasm"
  echo "    wasm $(human "$wasm_before") → $(human "$(size "$STAGE_DIR/index.wasm")")"
else
  echo "    ⚠ wasm-opt not found (brew install binaryen) — skipping wasm optimization"
fi

# --- 3. brotli the big two ---------------------------------------------------
echo "──▶ brotli -q 11 index.wasm + index.pck"
for f in index.wasm index.pck; do
  brotli -f -q 11 -o "$STAGE_DIR/$f.br" "$STAGE_DIR/$f"
  echo "    $f  $(human "$(size "$STAGE_DIR/$f")") → $(human "$(size "$STAGE_DIR/$f.br")")  (.br)"
done

# --- 4. assemble web-dist ----------------------------------------------------
echo "──▶ assembling web-dist/"
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"

# Ship everything the engine emits EXCEPT the uncompressed wasm/pck (we only
# serve their .br siblings). copy: html, js, worklets, icons, splash, .br files.
shopt -s nullglob
for src in "$STAGE_DIR"/*; do
  base="$(basename "$src")"
  case "$base" in
    index.wasm|index.pck) continue ;;   # superseded by the .br siblings
  esac
  cp "$src" "$DIST_DIR/$base"
done
shopt -u nullglob

# Vendored brotli decoder + the boot shim.
cp "$VENDOR_DIR/brotli_dec_wasm.js"      "$DIST_DIR/brotli_dec_wasm.js"
cp "$VENDOR_DIR/brotli_dec_wasm_bg.wasm" "$DIST_DIR/brotli_dec_wasm_bg.wasm"
cp "$SCRIPT_DIR/web/mb_brotli_boot.js"   "$DIST_DIR/mb_brotli_boot.js"

# Inject the boot shim into <head> so it installs the fetch override before
# index.js runs. Idempotent: index.html is freshly exported each run.
python3 - "$DIST_DIR/index.html" <<'PY'
import sys
p = sys.argv[1]
html = open(p, encoding="utf-8").read()
tag = '\t\t<script src="mb_brotli_boot.js"></script>\n'
assert "mb_brotli_boot.js" not in html, "shim already present (unexpected on a fresh export)"
assert "</head>" in html, "no </head> in exported index.html"
html = html.replace("</head>", tag + "\t</head>", 1)
open(p, "w", encoding="utf-8").write(html)
print("    injected mb_brotli_boot.js into <head>")
PY

# --- summary -----------------------------------------------------------------
total_br=$(( $(size "$DIST_DIR/index.wasm.br") + $(size "$DIST_DIR/index.pck.br") ))
decoder=$(( $(size "$DIST_DIR/brotli_dec_wasm.js") + $(size "$DIST_DIR/brotli_dec_wasm_bg.wasm") ))
echo
echo "──────── web-dist ready ────────"
echo "  wasm.br + pck.br transfer:  $(human "$total_br")"
echo "  brotli decoder overhead:    $(human "$decoder")"
echo "  output: ${DIST_DIR#$REPO_DIR/}"
echo
echo "  preview:  (cd web-dist && python3 -m http.server 8000)  →  http://localhost:8000"
echo "  deploy:   commit web-dist/ + customHttp.yml + amplify.yml, push to the Amplify-connected branch"
