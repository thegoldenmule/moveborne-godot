# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A multi-component workspace for **Moveborne** (a 2048-style swipe-merge puzzle), centered on a
Godot 4.6 port of the originally TypeScript/PixiJS client. The top-level directories are
**independent projects**, each with its own toolchain and its own notes:

| Dir | Project | Toolchain |
|---|---|---|
| `game/` | The Godot 4.6 (GDScript) game client + pure rules engine | Godot 4.6.3 |
| `validator/` | Self-contained move-validation service (deployable as a Snapser BYOSnap) | Bun + Hono + Socket.IO |
| `wiki/` | Committed mirror of the `hypercasual-llm` architecture wiki (ADRs + subsystem docs) | served via `wiki` MCP |
| `snapser-docs/` | Vendored Snapser platform docs + swagger (reference only, not built) | — |
| `art/` | Source art (`MoveBorne.psd`), extracted renders (`extracted/`), and the visual style guide | — |

## The one idea everything rests on

**Determinism parity.** `game/logic/` (GDScript) is a byte-for-byte port of
`@spyre-io/moveborne-logic` — the TS package whose prebuilt dist ships in `validator/src/logic/`.
Both compute **identical state hashes**, which is what lets the Godot client play against the
validator unchanged. The operational consequence: **never change `game/logic/` behavior without
re-running the parity tests** — a changed golden hash means you broke compatibility. TS source of
truth: `~/projects/thegoldenmule/moveborne/src/logic/src`.

Don't restate the architecture here — read the canonical pages:

| To understand… | Read |
|---|---|
| Overview, controls, project layout | `game/README.md` |
| Architecture, phase status, per-subsystem source-of-truth map | `game/GODOT_PORT_PLAN.md` |
| Godot/GDScript working notes + hard-won gotchas + parity-test loop | `game/CLAUDE.md` |
| Driving the game via MCP (the `MbDebug` autoload) | `game/MCP_GAME_API.md` |
| Native VFX mapping | `game/VFX_MAPPING.md` |
| Art direction ("occult arcade" violet-on-black), palette, typography | `art/STYLE_GUIDE.md` |
| Running the validator, its HTTP/Socket.IO/MCP endpoints, history replay | `validator/README.md`, `validator/src/validator/CLAUDE.md` |
| Design rationale (determinism, optimistic reconciliation, hard wall, …) | `wiki/hypercasual-llm/adrs/` |
| Subsystem architecture (client + validator) | `wiki/hypercasual-llm/architecture/` |

> The `wiki/` markdown is an **emitted mirror** of the *Hypercasual LLM* workspace, served by the
> `wiki` MCP server (`:4439`). **Edit wiki content through the MCP** (`mutatePage` / `mutatePageBatch`),
> never by hand: a live emitter regenerates the `.md` files + `.wiki-md-manifest.json` from the
> workspace on every change, so direct edits get overwritten. Read the files freely; treat them as
> read-only on disk.

## Commands

### Game (`game/` is the Godot project root)

```bash
# Open game/ in Godot 4.6.3 and press Play (main scene: res://scenes/main.tscn). Runs fully offline.

# Headless parity verifier (run from game/, or pass --path game). One per logic module:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
    --script res://tools/verify_engine_swipe.gd        # prints VERIFY ...: PASS/FAIL
# Verifiers: engine_swipe, playcard, powercards, validation, tile_effects, totems,
# events, scenarios, combined, and the validator client.
```

Editor test suites (`McpTestSuite`) run via the `godot-ai` MCP `test_run`, not the CLI. After editing
a `.gd` file, `filesystem_manage reimport` the changed paths. See `game/CLAUDE.md` for the full loop.

### Validator (`validator/`, Bun workspace)

```bash
cd validator
bun install            # installs deps + links the src/logic workspace
bun run dev            # hot-reload (bun --watch); HTTP + Socket.IO + MCP on :5555
bun run build          # rebuild src/logic/dist from its TS source (only when logic changes)
bun run test           # run the logic package's tests
bun run type-check     # tsc --noEmit on the validator
```

`src/logic/dist` is **committed** so the service runs without a build step. Don't kill/restart a
`bun run dev` process — `--watch` reloads on change.

### Snapser BYOSnap deploy (the validator, containerized)

`validator/Dockerfile` → Snapser `byosnap-validator` (profile: `validator/snapser-byosnap-profile.json`,
app `c4n1awfs`). Notes: **build context MUST be `validator/`** (so the `workspace:*` link resolves);
container listens on **:8080**; the gateway forwards the full prefix (`BYOSNAP_BASE_PATH`,
e.g. `/v1/byosnap-validator`) without stripping it, so routes are served under that base path while
`/health` is also answered unprefixed for the platform probe.

## Online play (game ⇄ validator)

The game client and all tooling target **one validator on `:5555`** — the self-contained `validator/`
in this repo:

- Start it: `tools/run_validator.sh` (one-shot wrapper) **or** `cd validator && bun run dev` **or** the
  `run-validator` skill. All serve `:5555` in DEV_MODE.
- In-game, press **`V`** to connect (`game/scenes/main.gd` → `VALIDATOR_URL = http://localhost:5555`).
  The HUD shows `validator: ✓ move N ok`; on a hash mismatch the client snaps to authoritative state.

## MCP servers & skills

`.mcp.json` registers three servers (enabled in `.claude/settings.local.json`):

- **`validator`** (`:5555/mcp`) — inspect/debug match state: `list_matches`, `get_match_state`,
  `get_state_history`, `simulate_action`, `clear_match`. **Start the validator first.**
- **`wiki`** (`:4439/mcp`) — the structured architecture wiki / ADRs.
- **`snapser`** (`npx @snapser/mcp-server-snapser`, app `c4n1awfs`) — the Snapser platform.
- The **`godot-ai`** MCP (bundled under `game/addons/`) drives the Godot editor/game.

Project skills (`.claude/skills/`): **`run-validator`** (start/stop/inspect the `:5555` validator) and
**`snapser-validator`** (anonymous-login + hit validator endpoints through the Snapser gateway).

## Conventions

- **Git: commit directly to `main`.** Don't create feature branches and don't ask to.
- Keep `game/logic/` free of Node/scene deps; it is pure static `class_name Mb*` utilities.
- Prove any logic change preserves hashes with a golden vector generated from the real TS dist before
  committing — never hand-write expected hashes (see `game/CLAUDE.md`).
