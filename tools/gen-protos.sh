#!/usr/bin/env bash
# Regenerate everything derived from the protobuf source of truth
# (validator/protos/) — run this whenever a .proto changes:
#
#   1. JS SDK        — the compiled descriptor the validator loads at runtime
#                      (validator/src/validator/proto-gen/validator-descriptor.json)
#   2. Swagger       — validator/swagger.json (Snapser uploads it on byosnap publish;
#                      version is pulled from package.json)
#   3. GDScript SDK  — godobuf bindings for the game
#                      (game/net/proto/{hermes_envelope_pb.gd,validator_pb.gd})
#
# Usage:  tools/gen-protos.sh                 # regenerate all three
#         GODOT=/path/to/Godot tools/gen-protos.sh
#         tools/gen-protos.sh --skip-gdscript # JS SDK + swagger only (no Godot needed)
#
# After regenerating, rebuild/redeploy the BYOSnap so Snapser picks up the new
# swagger (snapctl byosnap publish + sync), and re-run the parity check:
#   godot --headless --path game --script res://tools/verify_hermes_proto.gd
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="$ROOT/validator/protos"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SKIP_GDSCRIPT=0
[ "${1:-}" = "--skip-gdscript" ] && SKIP_GDSCRIPT=1

echo "→ [1/3] JS SDK (compiled descriptor) + [2/3] swagger.json"
( cd "$ROOT/validator" && bun run gen:proto )

if [ "$SKIP_GDSCRIPT" = "1" ]; then
  echo "→ [3/3] GDScript bindings — SKIPPED (--skip-gdscript)"
  echo "✓ JS SDK + swagger regenerated."
  exit 0
fi

if [ ! -x "$GODOT" ]; then
  echo "→ [3/3] GDScript bindings — SKIPPED: Godot not found at '$GODOT'"
  echo "  Set GODOT=/path/to/Godot and re-run, or pass --skip-gdscript."
  exit 0
fi

echo "→ [3/3] GDScript bindings (godobuf)"
# godobuf's --input must be an OS path (not res://); --output is res://.
# Codegen exits 0 even on failure, so assert the success line per file.
gen_gd() {
  local proto="$1" out="$2"
  local log
  log="$("$GODOT" --headless --path "$ROOT/game" -s res://addons/godobuf/godobuf_cmdln.gd \
    --input="$proto" --output="$out" 2>&1)"
  if ! grep -q "Compiled .* to '$out'" <<<"$log"; then
    echo "$log" | grep -iE "error|failed" || echo "$log" | tail -5
    echo "✗ godobuf failed for $proto"
    exit 1
  fi
  echo "  ✓ $out"
}
gen_gd "$PROTO_DIR/hermes/hermes_envelope.proto" "res://net/proto/hermes_envelope_pb.gd"
gen_gd "$PROTO_DIR/moveborne/validator/v1/validator_messages.proto" "res://net/proto/validator_pb.gd"

echo "✓ JS SDK, swagger, and GDScript bindings regenerated."
echo "  Next: redeploy the BYOSnap (snapctl byosnap publish + sync) so Snapser picks up swagger.json,"
echo "  and run: godot --headless --path game --script res://tools/verify_hermes_proto.gd"
