# Testing plan — Shared editor-tool styling (occult-arcade theme)

**Status:** ready

## Planned
_None._

## Passed
- verify_editor_tool_kit passes headless after each phase (Godot --headless --script res://tools/verify_editor_tool_kit.gd → VERIFY editor_tool_kit: PASS).
- tool_theme.build() returns a Theme whose expected type-items exist (Button/TabContainer/TabBar/PanelContainer/Panel/HSeparator + the Phase-2 input types) and whose colors/metrics equal the EditorToolPalette constants — asserted headless.
- Phase 0 is visually a no-op: artgen + story_map docks load and parse, and the rendered look is unchanged from commit 36e5732 (palette refactor only).
- Every themed control shows correct states: Button normal/hover/pressed/disabled/focus; LineEdit/SpinBox/OptionButton/TextEdit focus + read-only/disabled; Tree/ItemList selection — none render broken (no missing/black styleboxes).
- Per-control overrides still win over the cascade: artgen preview panel (black/checkerboard) and story-map dot markers (violet/green via restyle_selected) are unaffected by the shared Theme.
- TabContainer tabs render the intended look (dim unselected → violet-top-ruled selected with brighter text) in the Story Map dock.
- Major sections read as bordered groups (EditorToolUi.section) and bare HSeparator.new() sites now show the themed deep-violet rule.
- Human in-editor visual pass: open both docks in Godot 4.6.3, confirm cohesive occult-arcade styling and legibility of dense forms (paths/JSON/IDs) at editor-default font.

## Failed
_None._

## References
_None._

## Child pages
_None._
