#!/usr/bin/env bash
# Run THIS repo's validator locally (authoritative move validation, no Nakama).
#
# Convenience wrapper around the self-contained `validator/` Bun workspace at the
# repo root. Its `@spyre-io/moveborne-logic` dep is the prebuilt dist committed
# under validator/src/logic, so no external moveborne checkout or dep cache is
# needed — `bun install` links the workspace and the service runs as-is.
#
# The game client (scenes/main.gd) and the `validator` MCP server (.mcp.json)
# both target :5555. For iterative work prefer `cd validator && bun run dev` (or
# the run-validator skill); this script is the one-shot equivalent.
#
# Usage:  tools/run_validator.sh           # runs on :5555
#         PORT=3000 tools/run_validator.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../../validator"
PORT="${PORT:-5555}"

if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
  echo "Validator already running on :$PORT — nothing to do."
  exit 0
fi

cd "$VALIDATOR"
[ -d node_modules ] || bun install

# No gateway in front locally, so callers self-stamp the User-Id the validator
# requires (== player_id) — see scenes/main.gd / test_validator_client.gd.
echo "Starting in-repo validator on :$PORT"
exec env \
  VALIDATOR_SHARED_SECRET="${VALIDATOR_SHARED_SECRET:-dev-secret}" \
  PORT="$PORT" bun run dev
