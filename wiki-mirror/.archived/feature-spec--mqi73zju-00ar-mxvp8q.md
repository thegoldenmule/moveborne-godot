# Spec — Shared editor-tool styling (occult-arcade theme)

**Status:** sealed

## Overview
Both in-editor authoring tools (ArtGen, Story Map) now share one "occult-arcade" look with no per-dock styling code. A single EditorToolPalette holds the colors + metrics; EditorToolTheme.build() assembles a Theme from it that EditorToolPlugin assigns to the dock wrapper (_panel_root), so it cascades via Control.theme to every descendant of both docks — and any future tool inherits the look for free. Covers chrome and input controls with full control-state coverage, using the editor-default font (hierarchy from size / weight / color, no font import). Shipped in commits ea88136 + f4eb5da.

## Design
## Mechanism

EditorToolPalette (tool_palette.gd) is the single source of truth — one violet accent (#b400ff, hover #d24bff) on near-black, green #44ff88 for selection, white for peak emphasis (value-not-hue). It is owned by the tool kit and never loads the game theme (game/ui/theme/moveborne_ui.tres); the values are duplicated by intent so the two surfaces stay visually aligned yet fully decoupled.

EditorToolTheme.build() -> Theme styles chrome (Button/OptionButton, Tab*, Panel*, separators, Label) and input controls (LineEdit/TextEdit/SpinBox/Tree/ItemList/PopupMenu), each with normal/hover/pressed/disabled/focus + read-only/selection coverage so no control renders a missing stylebox. EditorToolPlugin assigns the built Theme to _panel_root, cascading to every dock descendant. Per-control overrides — the ArtGen preview panel, Story Map dot markers via restyle_selected, and EditorToolUi.section frames — still win locally over the cascade.

EditorToolUi.section(caption, body) frames a major block as a captioned, violet-bordered group. Verified headlessly via tools/verify_editor_tool_kit.gd (Theme is a plain Resource, constructible without the editor); the in-editor visual pass is a human step.

## Decisions
Theme reach: chrome + input controls. Style LineEdit / SpinBox / OptionButton / TextEdit / Tree / ItemList with full state coverage, not just header / tabs / buttons / sections — partial coverage makes editor controls look broken. How far should the shared theme reach — chrome only, or chrome + input controls?

Typography: editor-default font everywhere. No custom font import; hierarchy comes from size, weight, and color. The header title shares the editor-default font size (so it matches the version tag + reload button) and reads as the heading via the white emphasis color. Use the brand Grammara font for headers/captions, or the editor-default font?

## References
_None._

## Child pages
_None._
