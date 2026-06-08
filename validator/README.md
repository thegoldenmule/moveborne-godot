# Validator Service

Real-time game-state validation service, copied from the Moveborne project and
made self-contained for this repo. It validates moves, verifies state hashes, and
exposes an MCP server for inspecting and debugging match state.

## Layout

```
validator/
├── package.json          # Bun workspace root (workspaces: src/*)
├── .env.example          # config template (real .env lives in src/validator/)
├── src/
│   ├── validator/        # the service (Bun + Hono + Socket.IO + MCP)
│   └── logic/            # @spyre-io/moveborne-logic — game rules (workspace dep)
```

`src/validator` depends on `src/logic` via the `workspace:*` protocol; Bun links
it automatically on `bun install`. `src/logic/dist` is committed so the service
runs without a build step (rebuild with `bun run build` when the logic changes).

## Setup

```bash
cd validator
bun install                       # installs deps + links the logic workspace
cp src/validator/.env.example src/validator/.env   # already present; edit as needed
```

For production, set a strong secret in `src/validator/.env`:

```bash
VALIDATOR_SHARED_SECRET=$(openssl rand -hex 32)
DEV_MODE=false
```

## Run

```bash
cd validator
bun run dev      # hot-reload (bun --watch), uses PORT from .env (5555)
# or
bun run start
```

HTTP, Socket.IO, and the MCP interface all share one port (5555 by default):

- Health:   `GET  http://localhost:5555/health`
- Status:   `GET  http://localhost:5555/api/status`
- Match:    `POST http://localhost:5555/api/match/init`
- Socket.IO:`/socket.io/`
- MCP:      `POST http://localhost:5555/mcp`

## Use from Claude Code

This repo is already wired to use the validator:

- `.mcp.json` registers the `validator` MCP server at `http://127.0.0.1:5555/mcp`.
- `.claude/settings.local.json` enables it.
- The `run-validator` skill (`.claude/skills/run-validator/`) starts, stops, and
  inspects the service. Its `start-validator.sh` launches the validator on 5555.

Start the validator first (so the MCP server is reachable), then the
`mcp__validator__*` tools become available for listing matches, inspecting state,
simulating actions, and reading state history.
