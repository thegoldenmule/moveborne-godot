# Editor Tools

**Status:** current

## Kind
module

## Summary
In-editor asset tooling that runs inside the Godot editor rather than in the game. Currently one tool lives here: the **SVG Trim** tool — a Photoshop-style "Trim" that crops a generated SVG's viewBox to the smallest rect containing visible content. It complements the ArtGen pipeline (`addons/artgen/`): Recraft vector outputs arrive with large transparent borders after background stripping, and trim removes them so icons render at their full size in UI slots.

## Purpose
Generated vector art is authored on a fixed square canvas (Recraft emits 2048×2048), but the drawn glyph usually occupies a fraction of it — the shipped nav icons carried borders so large that one icon's content was only 684×932 of the canvas. UI code sizing a texture box then renders mostly empty space and the icon looks tiny. Trimming at the asset level (rather than per-consumer fudge factors) keeps every consumer honest: a 60px box shows ~60px of visible glyph. The tool is deliberately raster-based so it never needs to understand path data, transforms, or curves — anything ThorVG can draw, it can trim.

## Design notes
Algorithm: rasterize the SVG through ThorVG with the long edge scaled to roughly the requested raster size, take the image's used rect — the smallest rect containing pixels with non-zero alpha — then grow it by one raster pixel per side to cover anti-aliased edges cut at raster resolution. Map that pixel rect back into viewBox units, apply the optional margin, and intersect with the original viewBox. The width and height attributes are rescaled by the same ratio as the viewBox, so the imported texture's pixel density is unchanged by cropping.

```gdscript
# Pure static helper (no editor/scene deps) on the ArtGen SVG toolbox:
var res := ArtgenSvg.trim_to_content(svg_text)          # defaults: margin 0, ~512px raster
if res["status"] == ArtgenSvg.STATUS_TRIMMED:
    save(res["text"])                                   # res["rect"] = trimmed viewBox
# statuses: trimmed | empty | no_viewbox | raster_failed
```

Trimming changes aspect ratios: a square canvas becomes a content-shaped rect, so consumers that stretched square textures must switch to keep-aspect rendering. The app shell's nav bar did exactly this when the icons were trimmed (stretch-to-fill would have distorted them). New consumers of generated SVGs should assume non-square textures from the start.

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- function `ArtgenSvg.trim_to_content` in `game/addons/artgen/svg_tools.gd`
- `game/tools/trim_svg_editor.gd`
- `game/tools/verify_artgen_svg.gd`

## Data model
`trim_to_content` returns `{"text": String, "status": String, "rect": Rect2}` where `text` is the rewritten SVG, `rect` the trimmed viewBox (only on success), and `status` one of: `trimmed` (success), `empty` (no visible content — file left untouched rather than producing a zero rect), `no_viewbox` (missing/degenerate viewBox attribute), `raster_failed` (ThorVG could not rasterize). Only the `viewBox`, `width`, and `height` attributes change; path data and all other markup pass through byte-identical.

## Usage
**In-editor (the normal path):** select `.svg` files or folders in the FileSystem dock, open `game/tools/trim_svg_editor.gd` in the Script editor, and run it (File > Run, Cmd/Ctrl+Shift+X). Each file is trimmed in place, reimported, and its cropped rect printed; non-trimmable files (empty, no viewBox) are skipped with a reason. The run is idempotent — re-trimming an already-trimmed file is a no-op rewrite. `MARGIN_FRAC` at the top of the script adds padding as a fraction of the cropped long edge if breathing room is wanted.

**Programmatic:** call `ArtgenSvg.trim_to_content(svg_text, margin_frac := 0.0, raster_px := 512)` from any editor or game context — it is a pure static helper with no editor/scene deps.

**Verification:** trim behavior is covered by the headless verifier `godot --headless --path game --script res://tools/verify_artgen_svg.gd` (known rect round-trips within raster tolerance; fully transparent SVGs are refused).

After trimming saved ArtGen assets, the artgen audit flags them `modified_after_save` in `ai_manifest.json` — expected, since trim is a post-save edit of a promoted asset.

## Invariants & constraints
- Trim never parses or rewrites path data — only the viewBox, width, and height attributes change; everything else passes through byte-identical.
- Imported pixel density is preserved: width/height attributes rescale by the same ratio as the viewBox, so cropping never changes px-per-viewBox-unit at import.
- Trim is idempotent and refuses degenerate output: an already-trimmed file re-trims to the same rect, and a fully transparent SVG returns status "empty" instead of a zero-size viewBox.

## Synced commit
2188324
