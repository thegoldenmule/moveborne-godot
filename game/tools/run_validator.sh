#!/usr/bin/env bash
# Run the Moveborne validator in DEV_MODE (authoritative move validation, no Nakama).
#
# The validator's package.json declares `@spyre-io/moveborne-logic: workspace:*`,
# which bun can't resolve standalone (the monorepo uses pnpm). So we install its
# registry deps + the logic package's runtime deps into a persistent dir, drop the
# prebuilt logic dist in as a real package, and point the validator's node_modules
# there. The validator's OWN code is run unchanged.
#
# Usage:  tools/run_validator.sh           # sets up (idempotent) and runs on :5055
#         PORT=3000 tools/run_validator.sh
set -euo pipefail

MOVEBORNE="/Users/benjaminjordan/projects/thegoldenmule/moveborne"
VAL="$MOVEBORNE/src/validator"
LOGIC="$MOVEBORNE/src/logic"
DEPS="$HOME/.cache/moveborne-validator-deps"
PORT="${PORT:-5055}"

if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
  echo "Validator already running on :$PORT — nothing to do."
  exit 0
fi

if [ ! -d "$DEPS/node_modules/socket.io" ]; then
  echo "Installing validator deps in $DEPS ..."
  mkdir -p "$DEPS"
  cat > "$DEPS/package.json" <<'JSON'
{ "name": "moveborne-validator-deps", "private": true, "type": "module",
  "dependencies": {
    "@hono/mcp": "^0.1.5", "@modelcontextprotocol/sdk": "^1.20.2",
    "@socket.io/bun-engine": "^0.0.3", "hono": "^4.10.4", "socket.io": "^4.8.1",
    "seedrandom": "^3.0.5", "json-stable-stringify": "^1.3.0" } }
JSON
  (cd "$DEPS" && bun install)
fi

# Prebuilt logic package as a real dir (so its bare imports resolve up to $DEPS/node_modules).
mkdir -p "$DEPS/node_modules/@spyre-io/moveborne-logic"
cp "$LOGIC/package.json" "$DEPS/node_modules/@spyre-io/moveborne-logic/package.json"
rm -rf "$DEPS/node_modules/@spyre-io/moveborne-logic/dist"
cp -r "$LOGIC/dist" "$DEPS/node_modules/@spyre-io/moveborne-logic/dist"

ln -sfn "$DEPS/node_modules" "$VAL/node_modules"

echo "Starting validator on :$PORT (DEV_MODE — Nakama signature check disabled)"
cd "$VAL"
exec env VALIDATOR_SHARED_SECRET="${VALIDATOR_SHARED_SECRET:-dev-secret}" DEV_MODE=true PORT="$PORT" bun run index.ts
