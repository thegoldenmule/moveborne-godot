# Feature: Shared editor-tool styling (occult-arcade theme)

**Status:** shipped

## Summary
The two in-editor authoring tools — **ArtGen** and **Story Map** — currently inherit Godot's raw editor chrome, and what little styling exists (`tool_header`, `restyle_selected`, and scattered `add_theme_color_override` literals across both docks) duplicates the same violet / near-black values by hand. This feature gives `addons/editor_tool_kit/` a **shared "occult-arcade" theme** so every tool reads as one cohesive surface: styled headers, tabs, buttons, input controls, and bordered sections.

The mechanism is Godot's `Control.theme` cascade — `EditorToolPlugin` assigns one shared `Theme` to the dock wrapper (`_panel_root`), so it reaches every descendant of both docks with **no per-dock styling code**, and any new tool inherits the look for free. A single `EditorToolPalette` holds the colors + metrics that `tool_header`, `restyle_selected`, the theme, and the docks all reference, replacing today's scattered literals.

Reuses the established palette from `game/ui/theme/moveborne_ui.tres` and `art/STYLE_GUIDE.md`: one violet accent (`#b400ff`, hover `#d24bff`) on near-black, green `#44ff88` for selection, white reserved for peak emphasis — value-not-hue hierarchy.

**Decided scope:** chrome **+ input controls**; **editor-default font** (hierarchy via size / weight / color — no font import). Lands in phases, each a clean commit so the look can be eyeballed as it builds up.

## Components affected
- EditorToolPalette (tool_palette.gd) — single source of truth: colors + metrics
- EditorToolTheme (tool_theme.gd) — build() -> Theme covering chrome + input controls
- EditorToolPlugin theme injection — assign the Theme to _panel_root; cascades to every dock
- EditorToolUi.section() — bordered, captioned group container + themed separators
- Palette refactor — repoint tool_header, restyle_selected, and dock ad-hoc colors at the palette
- verify_editor_tool_kit — headless assertions for the theme + palette wiring

## Design constraints
1. Editor-only addon: no runtime/game dependency; everything runs under @tool.
2. Theme applied via the Control.theme cascade on _panel_root — no per-dock styling code; a new tool inherits the look automatically.
3. Cover every control state (normal/hover/pressed/disabled/focus, plus selection/read-only) — partial state coverage makes editor controls look broken.
4. Body/field text keeps the editor-default font; no custom font import (hierarchy comes from size, weight, and color).
5. Per-control overrides (artgen preview panel; story-map dot markers via restyle_selected) must still win locally over the cascaded theme.
6. Phase 0 (palette consolidation) is a no-op visual refactor — appearance must not change.
7. Verify headlessly (Theme is a plain Resource, constructible without the editor); the human does the in-editor visual pass — do not puppeteer the running editor.
8. The tool kit OWNS its default Theme (the occult-arcade look): tool_theme.gd builds it from tool_palette.gd and EditorToolPlugin applies it. It must NOT load or reference the game's theme (game/ui/theme/moveborne_ui.tres) — the palette values are duplicated by intent so the two surfaces stay visually aligned yet fully decoupled (editing one never affects the other).
9. Palette per art/STYLE_GUIDE.md: one violet accent (#b400ff, hover #d24bff) on near-black, green #44ff88 for selection, white reserved for peak emphasis (value-not-hue hierarchy). The default applies automatically via the cascade; a tool may still override it on its own dock if ever needed.

## Open questions
_None._

## Resolved questions
1. **How far should the shared theme reach — chrome only, or chrome + input controls?** — _Chrome + input controls. Also style LineEdit / SpinBox / OptionButton / TextEdit / Tree / ItemList (full state coverage), not just header/tabs/buttons/sections._
2. **Use the brand Grammara font for headers/captions, or the editor-default font?** — _Editor-default font everywhere. No custom font import; rely on size / weight / color for hierarchy. (Headers don't need a font either, so there is no font-import work.)_

## References
- extends → [Editor Tool Framework](architecture:mqh31a29-0001-sy7uqn)

## Child pages
- [Implementation plan — Shared editor-tool styling (occult-arcade theme)](implementation-plan:mqi73zju-00ap-2e62fy)
- [Testing plan — Shared editor-tool styling (occult-arcade theme)](testing-plan:mqi73zju-00aq-8qfv96)
- [Spec — Shared editor-tool styling (occult-arcade theme)](feature-spec:mqi73zju-00ar-mxvp8q)

## Commits
- `ea88136` feat(editor): shared occult-arcade theme for the editor tool kit
- `f4eb5da` fix(editor): header sizing + tab spacing polish for the tool theme
