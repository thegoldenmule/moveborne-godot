# Implementation plan — Shared editor-tool styling (occult-arcade theme)

**Status:** ready

## Steps
- [x] Phase 0a — Add tool_palette.gd (class_name EditorToolPalette): colors + metrics as the single source of truth (see data model below).
- [x] Phase 0b — Repoint tool_header + restyle_selected to read from EditorToolPalette. No visual change.
- [x] Phase 0c — Replace ad-hoc color/separation literals in the artgen + story_map docks with palette refs (dim-violet captions, usage-state colors, white marker labels, repeated separation=8). No visual change.
- [x] Phase 1a — Add tool_theme.gd build() -> Theme covering the chrome: Button (normal/hover/pressed/disabled/focus), TabContainer + TabBar (dim unselected → violet-top-ruled selected), PanelContainer/Panel, HSeparator/VSeparator (deep-violet rule), Label defaults — all from the palette.
- [x] Phase 1b — Assign the built Theme to _panel_root in EditorToolPlugin so it cascades to every dock; confirm per-control overrides (preview panel, dot markers) still win locally.
- [x] Phase 2 — Extend tool_theme to input controls: LineEdit, TextEdit, SpinBox (+ up/down), OptionButton (Button + popup), Tree, ItemList — normal/focus/read-only/disabled styleboxes + selection colors, from the palette.
- [x] Phase 3a — Add EditorToolUi.section(caption, body) -> PanelContainer (violet border, padded, captioned) so major sections read as framed groups.
- [x] Phase 3b — Adopt section() for the major sections (artgen compose/gallery/detail; story_map Goals/Rewards blocks) and replace bare HSeparator.new() with the themed separator or section frames.
- [x] Phase 4a — Extend verify_editor_tool_kit to assert tool_theme.build() wires the expected type-items and pulls its values from EditorToolPalette (headless; Theme is a plain Resource).
- [x] Phase 4b — Update addons/editor_tool_kit/README.md primitives list (palette, theme, section) and note the Control.theme cascade mechanism. Human does the in-editor visual pass.

## Data models & interfaces
```gdscript
class_name EditorToolPalette
extends RefCounted
## Single source of truth for editor-tool styling, OWNED by the tool kit — NO
## dependency on the game theme (game/ui/theme/moveborne_ui.tres is never loaded).
## One violet accent on near-black; white = peak emphasis (art/STYLE_GUIDE.md).
## Values are chosen to echo the game UI but are duplicated by intent — the two
## surfaces stay visually aligned yet fully decoupled.

# --- Colors ---
const VIOLET       := Color("b400ff")              # borders, active accents
const VIOLET_HOVER := Color("d24bff")              # hover border
const VIOLET_DEEP  := Color("43005d")              # dim rules / empty outlines
const GREEN_SEL    := Color("44ff88")              # selection / active marker accent
const PANEL_BG     := Color(0.078, 0.078, 0.110)   # control normal fill
const PANEL_HI     := Color(0.137, 0.125, 0.227)   # hover fill
const TEXT         := Color(0.925, 0.925, 0.957)   # primary near-white
const TEXT_DIM     := Color(0.55, 0.50, 0.60)      # secondary (version, captions)

# --- Metrics ---
const BORDER    := 2
const CORNER    := 6      # tighter than the game UI's 10, for editor density
const SEP       := 8
const H_TITLE   := 20     # tool_header title
const H_CAPTION := 14     # section captions
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
