# Presentation &amp; VFX

**Status:** current

## Kind
subsystem

## Summary
The presentation layer: `scenes/main.gd`/`.tscn` (playable scene — HUD, hand, targeting, scenarios, status) and `board_view.gd` (board render + input + spawn/merge tweens), plus VFX autoloads and shaders (`vfx.gd`, `anim.gd`, `quality.gd`, glow/glitch/twist `.gdshader`). Strictly read-only over game state.

## Purpose
Turn engine output into a playable, juicy screen and turn raw input into engine actions — without ever owning game logic. It renders the state `MbMatch` publishes, runs spawn/merge/black-hole/glitch VFX, and forwards arrow/drag/tap input as swipe/card actions. The hard wall (`input → action → engine → state → render`) keeps determinism unaffected by anything here.

## Design notes
_No design notes._

## Components
_No components._

## Dependencies
- **depends-on** → [Match Controller](architecture:mq1c2vaw-000p-3fdst6) — Renders state published by MbMatch and forwards input as actions to it.

## Code references
- `game/scenes/main.gd`
- `game/scenes/board_view.gd`
- `game/scenes/vfx.gd`
- `game/VFX_MAPPING.md`

## Data model
_None._

## Usage
`scenes/main.tscn` is the project main scene; press Play. Portrait 720×1560, GL Compatibility renderer (switched from Forward+ for stable FPS on macOS). A `Quality` autoload toggles glow/particle cost. Drive via MCP: `game_manage input_key` uses key *names* (`"Left"`, `"V"`); `get_ui_elements` returns rects for clicking; `editor_screenshot source:"game"` captures frames. Full VFX catalog: `VFX_MAPPING.md`.

## Invariants & constraints
- Presentation never mutates game state or RNG — it only reads what MbMatch publishes and emits input actions; VFX must be deterministically cleaned up (a prior leak of ~22k nodes tanked FPS).

## Synced commit
85f64c0
