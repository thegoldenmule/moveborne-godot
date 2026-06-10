# Testing plan — ArtGen — Recraft Asset Generation

**Status:** ready

## Planned
- M0 exit: custom style created from art/style_refs/; side-by-side test icons (custom style_id vs named 'Line art') generated and reviewed; SVG background-rect question answered with real output; ThorVG imports a generated SVG cleanly in Godot; default preset decided and pinned in config.json
- Generate (dock): icon-flat preset + subject produces n variations previewed on black; one ledger line per image with full params and cost; balance display updates after the call
- Palette discipline: generated icons are violet (#A100FF family) line-art only — no extra hues, no gradients, no baked glow (spot-check against art/STYLE_GUIDE.md do/don't list)
- Transparency: a saved icon renders correctly composited over a non-black background in a test scene (background genuinely stripped/removed, no black box)
- Save: file lands in res://assets/generated/icons/, import completes without manual rescan, ai_manifest.json entry written (generator, style_id, prompt, gen_id, sha256), and the texture is immediately usable in a scene
- History durability: after an editor restart the gallery shows the complete history with saved/discarded states correctly folded from ledger.jsonl; discarded files still exist on disk
- Lineage: Iterate from a generation records parent_id; the chain is navigable in the detail view and returned by artgen_get
- MCP loop (editor open): artgen_generate (preset icon-flat, n=3) returns absolute file paths readable by Claude; artgen_save promotes the chosen one and updates the manifest; the dock gallery refreshes live without user action
- MCP offline: with the editor closed, every artgen tool returns the clear 'editor not running / plugin disabled' error promptly — no hang, no stack trace
- Error paths: invalid API key fails validate with a readable message; zero balance refuses Generate with a top-up hint; an API error mid-batch writes an api_error ledger line and surfaces in dock + MCP response
- Secrets: the API key appears nowhere in git (project_metadata.cfg is gitignored; grep the repo); the shim process receives no key
- Manifest invariant: every file under res://assets/generated/ (except the manifest) has an entry; hand-editing a saved file flips modified_after_save on the next check
- Concurrency/limits: queueing 6+ generations processes serially without editor freeze (use_threads), never tripping the 5 req/s limit

## Passed
_None._

## Failed
_None._

## References
_None._

## Child pages
_None._
