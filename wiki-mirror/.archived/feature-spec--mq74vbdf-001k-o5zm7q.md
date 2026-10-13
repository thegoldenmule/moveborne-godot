# Spec — ArtGen — Recraft Asset Generation

**Status:** sealed

## Overview
Design for **ArtGen**: a self-contained Godot editor addon (`game/addons/artgen/`) that generates assets via the Recraft API in the `art/STYLE_GUIDE.md` occult-arcade style, with a human dock UI and a Claude-facing MCP surface sharing one in-editor service. Core loop: preset + subject → n variations → preview on black → iterate (lineage-linked) → explicit save into `res://assets/generated/` with AI attribution. All provider facts below were verified against Recraft's official docs and live OpenAPI spec on 2026-06-09. Supersedes the interim repo file `game/ARTGEN_SPEC.md` (deleted in favor of this page).

## Design
## Verified provider facts that shape the design

```text
FACT (verified 2026-06-09)                                  | CONSEQUENCE
------------------------------------------------------------+------------------------------------------------
No history API; images stored ~24 h on signed URLs,         | Download immediately; response_format b64_json
unrecoverable after. Only GETs: /v1/users/me, /v1/styles*.   | (no second fetch); keep our own committed ledger.
Custom styles persist server-side: POST /v1/styles           | One-time style creation from curated refs;
(multipart, <=5 imgs, PNG/JPG/WEBP, <=5 MB total, $0.04)     | style_id committed in config; GET /v1/styles
returns style_id.                                            | exists for recovery (OpenAPI-level).
style_id works on V3 ONLY (recraftv3, recraftv3_vector);     | Pin V3 models in config; never rely on the API
V4/V4.1 reject styles; recraftv4_1 is the current default.   | default. Revisit when styles land for V4.
style (named, e.g. "Line art") XOR style_id per request.     | Presets choose one; fallback preset uses style.
controls.colors + controls.background_color ({rgb:[r,g,b]})  | Every preset forces violet #A100FF + black.
work on ALL models; no transparent-background control.       | Transparency is post-processing.
Vector models return real SVG but take aspect ratios (1:1);  | Icon preset: vector 1:1, n 2-4. Card/texture:
raster takes 1024x1024. n = 1-6 per call.                    | raster sizes.
Utilities: removeBackground $0.01, vectorize $0.01,          | Costs trivial (8-icon bar in SVG ~ $0.70 incl.
crispUpscale $0.004. V3 raster $0.04, V3 vector $0.08/img.   | style). Balance via GET /v1/users/me -> credits.
Auth: Bearer token. Limits: 5 req/s, 100 img/min.            | Serial request queue is more than enough.
random_seed in OpenAPI spec but undocumented for             | Send if set, always record it, never depend
/generations.                                                | on it.
```

Flagged unverified, resolved by the M0 spike: whether generated SVGs bake in a full-canvas background rect (community says yes); custom-style quality from 5 or fewer reference images; whether ThorVG (Godot's SVG importer) handles Recraft SVG output cleanly.

## Architecture

ArtGen is its own MCP entry point rather than a godot-ai extension (see Decisions). It follows the repo's existing pattern of purpose-specific MCP servers (validator on 5555, wiki on 4439): command handlers run inside the editor process so save, reimport, and dock refresh all work, and Claude reaches them through a fourth entry in the MCP config. godot-ai remains the generic editor driver and is still used alongside, for example taking an editor screenshot to eyeball a saved icon in a scene.

```text
                                 +----------------- Godot editor process ------------------+
Claude --MCP(stdio)--> tools/artgen_mcp.ts --HTTP--> | bridge.gd (TCPServer :4848, localhost)           |
                       (Bun shim, no deps)           |     |                                            |
                                                     | artgen_service.gd (singleton in plugin)          |
Human ---------------------------------------------> |  dock UI --+-- recraft_client.gd (HTTPRequest) --+--> external.api.recraft.ai
                                                     |     |      +-- ledger   (art/generated/ledger.jsonl)
                                                     |     |      +-- manifest (res://assets/generated/ai_manifest.json)
                                                     |     |      +-- save pipeline (copy -> EditorFileSystem scan/reimport)
                                                     +--------------------------------------------------+
```

Key wiring: the service script is UI-free and emits history-changed and generation-completed signals; the dock subscribes, which is what makes MCP-triggered generations appear live in the gallery. The Recraft client creates one HTTPRequest child per in-flight call under the plugin's tree (HTTPRequest only works in-tree) and runs a serial queue with a 120-second timeout. The multipart helper hand-rolls form-data bodies (needed for style creation and background removal, sent through the raw-bytes request variant). The bridge holds each TCP connection open until async work completes, since a generation takes 10 to 60 seconds. The shim returns a clear error when the bridge port is closed: Godot editor not running, or ArtGen plugin disabled.

## Data model and file layout

```text
art/
  style_refs/                     # curated 1024^2 crops used to create the Recraft style (committed)
  generated/                      # EVERYTHING ever generated (committed)
    ledger.jsonl                  # append-only journal (one JSON object per line)
    2026-06/                      # bucketed by month
      g_1718000000_3f2a.svg
      g_1718000000_3f2a.meta.json # optional raw API response echo for debugging
    .thumbs/                      # dock thumbnail cache (gitignored)
game/
  assets/generated/               # ONLY saved/promoted assets (committed, imported by Godot)
    ai_manifest.json              # central AI-attribution manifest
    icons/icon_leaderboard.svg
    cards/...
  addons/artgen/                  # the addon (committed)
tools/
  artgen_mcp.ts                   # Bun stdio-MCP shim (committed)
```

History lives outside the Godot project root so hundreds of experiments do not churn the importer; the editor still reads the files via absolute paths resolved from the project directory. History is committed: that is the durable look-at-past-stuff store, since Recraft keeps nothing. If the directory ever gets heavy, prune by deleting image files of discarded entries; ledger lines are never deleted.

### Ledger (append-only journal)

```jsonc
// art/generated/ledger.jsonl - one JSON object per line
{"type":"generation","id":"g_1718000000_3f2a","ts":"2026-06-09T20:00:00Z","provider":"recraft",
 "model":"recraftv3_vector","style_id":"<uuid>|null","style":null,"preset":"icon-flat",
 "subject":"leaderboard","prompt":"<full final prompt>","negative_prompt":null,
 "size":"1:1","n":3,"n_index":0,
 "controls":{"colors":[{"rgb":[161,0,255]}],"background_color":{"rgb":[0,0,0]}},
 "random_seed":null,"parent_id":null,"image_id":"<recraft image_id>",
 "file":"art/generated/2026-06/g_1718000000_3f2a.svg","post":["strip_bg_rect"],
 "cost_units":80,"status":"ok|api_error|import_failed"}
{"type":"save","gen_id":"g_...","ts":"...","dest":"res://assets/generated/icons/icon_leaderboard.svg","sha256":"..."}
{"type":"discard","gen_id":"g_...","ts":"..."}
{"type":"style_created","ts":"...","style_id":"<uuid>","style":"vector_illustration",
 "refs":["art/style_refs/01.png"],"cost_units":40}
```

A generation's current state (new, saved, or discarded) is derived by folding events; the service keeps an in-memory index and rewrites nothing. Calls requesting several variations produce one generation line per image (shared prompt, distinct index, image id, and file). Lineage: iterate-on-this-one records the parent generation's id, so chains are inspectable in the dock and over MCP. Discard only hides an entry from the default gallery view; the file is kept.

### Attribution manifest

```jsonc
// res://assets/generated/ai_manifest.json
{ "version": 1,
  "assets": {
    "res://assets/generated/icons/icon_leaderboard.svg": {
      "generator": "recraft/recraftv3_vector",
      "style_id": "<uuid>",
      "prompt": "<full prompt>",
      "gen_id": "g_1718000000_3f2a",
      "generated_at": "...", "saved_at": "...",
      "sha256": "<of the saved file>",
      "post": ["strip_bg_rect"]
    } } }
```

Invariant: every file under the generated-assets folder except the manifest itself has an entry. Re-saving over an existing path overwrites the entry; the old version remains traceable via the ledger. The stored hash lets a later check detect hand-edited files; such an entry gets a modified-after-save flag rather than being blocked, since hand-polish is expected and fine. The manifest doubles as the AI-disclosure record for store questionnaires.

### Secrets and committed config

The API key is never committed: it is stored through the editor-settings project-metadata API (which lands in the gitignored per-project editor state folder), entered once in the dock's settings popup, with an environment-variable fallback (note a Finder-launched Godot does not inherit shell variables, so editor settings are primary). The Bun shim never sees the key; only the editor talks to Recraft. Committed config pins the style id, the fallback named style (Line art), the model ids for vector and raster, and the bridge port; the presets file encodes the style guide as data, not code.

```text
key storage:  EditorSettings.set_project_metadata("artgen", "api_key", ...)
              -> res://.godot/editor/project_metadata.cfg (gitignored)
env fallback: RECRAFT_API_KEY
config.json:  { "style_id": "<uuid>|null", "fallback_style": "Line art",
                "models": {"vector": "recraftv3_vector", "raster": "recraftv3"},
                "bridge_port": 4848 }
```

```text
PRESET            MODEL/SIZE          PROMPT TEMPLATE ({subject} interpolated)                     POST
icon-flat         vector, 1:1         flat minimalist line-art icon of {subject}, thin uniform     strip bg rect
                                      violet strokes on pure black, occult arcade wireframe
                                      style, single centered glyph, generous margins, no text,
                                      no gradients, no glow, no shading
icon-raster       raster, 1024x1024   same as icon-flat                                            removeBackground
card-glyph        vector, 2:3         abstract wireframe op-art tarot glyph of {subject},          strip bg rect
                                      single violet line-art figure on black, acid-graphics
                                      style, no text
card-illustrated  raster, 1024x1024   tarot card illustration of {subject}, violet line-work on    none (full-bleed)
                                      textured black, screen-print grain, ornamental border,
                                      memento-mori iconography, single accent color
texture           raster, 1024x1024   {subject}, seamless dark grunge screen-print texture,        none
                                      near-black, subtle violet, halftone grain

All presets attach controls (violet + black) and style_id when set (dropping style), else fallback_style.
```

## Dock UX (bottom panel: ArtGen)

Left, compose: a preset dropdown, subject and prompt editor with a collapsible preview of the resolved final prompt, a variations spinner (1 to 6), an Advanced foldout (model, size, style override, seed, raw controls JSON), and a Generate button with progress and status. Right, gallery: a scrolling thumbnail grid of the full ledger, newest first, with filter chips (all, new, saved, discarded) and text search over prompt and subject. Thumbnails are rendered once into a gitignored cache folder; SVGs are rasterized with the engine's built-in SVG loader.

Detail view on click: large preview with a background toggle (black versus checkerboard, since judging transparency on black is otherwise impossible), full metadata, lineage links to parent and children, and actions: Save (category and filename dialog, slug prefilled from subject), Iterate (prefills compose with this prompt and links the parent), More variations, Discard. Status strip: API balance refreshed after each call, cost of the last operation, bridge port state, configured style id. Settings popup: API key entry with validate, create or select a custom style (multi-file picker defaulting to the curated reference folder, enforcing the 5-file and 5 MB limits), bridge port.

## MCP surface

The MCP config gains an artgen entry running the Bun shim; file paths in responses are absolute, so Claude can Read images directly to look at them. Intended Claude loop: generate three variations with the flat-icon preset and a subject; Read the three files; pick one or iterate with the parent link; save with a name and category; optionally verify in-scene via a godot-ai editor screenshot. The shim sets no client timeout; the worst-case generation (six vector images) is about 60 seconds, under MCP defaults.

```text
TOOL                 PARAMS                                                        RETURNS
artgen_status        -                                                             editor/bridge state, balance units, style_ids
                                                                                   (config + GET /v1/styles), presets, history counts
artgen_generate      prompt OR (preset + subject), n?, model?, size?, style_id?,   array of {gen_id, file, cost_units, status} -
                     seed?, parent_id?, post?                                      blocks until done (10-60 s)
artgen_history       limit?, status?, query?, since?                               folded ledger entries, newest first
artgen_get           gen_id                                                        full record incl. lineage + absolute file path
artgen_save          gen_id, name, category (icons|cards|textures|misc)            {res_path} after copy + import + manifest write
artgen_discard       gen_id                                                        ack
artgen_style_create  files? (defaults art/style_refs/*), style?                    {style_id} (also written to config + ledger)
```

## Generation pipeline

```text
1. Build request from preset + overrides: resolve prompt template; attach controls;
   style_id XOR style; response_format b64_json; pin V3 model.
2. POST /v1/images/generations (serial queue). On HTTP/API error: ledger line with
   status api_error + message; surfaced in dock and MCP response.
3. Decode and write each b64_json image to art/generated/<YYYY-MM>/<gen_id>.<svg|png>
   immediately - nothing transient, crash-safe before post-processing.
4. Post-process per preset:
   - strip_bg_rect (SVG): remove full-canvas fill element(s) whose color ~= the
     requested background_color; overwrite only on success; record in post.
     (Heuristic validated in M0; if Recraft SVGs are clean this is a no-op.)
   - removeBackground (raster): multipart call, $0.01, replaces file; cost added.
5. Validate import: Image.load_svg_from_buffer / load_png_from_buffer; on failure
   mark import_failed (file kept for inspection).
6. Ledger append + signals -> dock gallery updates; MCP response returns.
7. Save (later, explicit): copy to res://assets/generated/<category>/<name>.<ext>
   -> EditorInterface.get_resource_filesystem().scan() -> await filesystem_changed
   -> manifest upsert -> ledger save event. Import options: Godot defaults in v1;
   revisit per-asset via .import rewrite + reimport_files if icons need it.
```

## Costs and limits

Style creation costs four cents one-time. A typical icon session (3 variations times 3 iterations, vector) is about 72 cents. A full 8-icon bottom bar with healthy iteration: a few dollars. Rate limits (5 requests per second, 100 images per minute) are unreachable with a serial queue. Recraft API units are prepaid (one dollar buys 1000 units, non-expiring); the dock shows balance and refuses Generate at zero with a link to the top-up page.

## Risks

```text
RISK                                              MITIGATION
Custom style from <=5 refs misses the look        M0 decides; fallbacks: curated style "Line art" + strong prompt +
                                                  color controls (already close to the style guide), or raster via
                                                  gpt-image-1.5 (research fallback) behind the same service interface.
SVG background-rect stripping is brittle          M0 inspects real output; worst case the default preset switches to
                                                  icon-raster + removeBackground ($0.05/icon total).
Recraft drops V3 before V4 gets style support     Styles are cheap to re-create; the ledger keeps all prompts/refs to
                                                  rebuild on any model. Config pin makes the dependency greppable.
Editor must be open for the MCP path              Accepted (matches godot-ai's own constraint). Stretch: headless
                                                  tools/artgen_cli.gd reusing the service (mind the call_deferred
                                                  HTTPRequest gotcha from game/CLAUDE.md).
Committed history grows large                     Month-bucketed dirs; prune = delete image files of discarded
                                                  entries, never ledger lines. Icons are ~10-500 KB.
Bridge port collision / second editor instance    Fixed port + env override; binds 127.0.0.1 only; second instance
                                                  logs a warning and runs dock-only.
```

## Decisions
Ship ArtGen's own MCP entry point instead of extending godot-ai. The godot-ai tool surface is defined in its external PyPI package (the editor-side tool catalog script is an explicit do-not-edit mirror of the package's domains module, CI-enforced upstream; handlers are hard-registered in its plugin script with no project-side hook), so adding an artgen domain means forking a third-party package. Instead, a zero-dependency Bun stdio MCP shim in tools/ proxies to a localhost HTTP bridge (TCP server on port 4848) inside the editor plugin - the repo's established purpose-specific-MCP pattern (validator, wiki). Handlers still run in the editor process, so save, reimport, and dock refresh work, and the human dock and Claude share one live service. If godot-ai later ships project-side tool registration, the bridge folds into it. Claude must be able to drive generation over MCP ('over the godot mcp'). Extend the bundled godot-ai server, or ship a separate entry point?

Track history ourselves, committed to git - the API cannot do it. Verified: Recraft has no list-past-generations endpoint, and image URLs expire after roughly 24 hours on signed links. Every generation is therefore requested as base64 JSON and written immediately into the month-bucketed history folder, journaled in the append-only ledger (event types: generation, save, discard, style-created) with full prompt, params, cost, and parent lineage. The gallery and the history MCP tool both fold this ledger; nothing depends on provider-side state except the reusable style objects, which the styles listing endpoint can recover. How do we track everything ever generated so past work stays browsable, given the provider may not store it?

History lives outside the Godot project, in the repo-root art folder. Keeping hundreds of experiments out of the project avoids importer churn (import sidecars, scan cost) entirely; the editor reads previews via absolute paths. Only explicitly promoted assets enter the generated-assets folder inside the project. Both stores are committed. Where should generation history live — inside res:// or outside the Godot project?

A single committed manifest inside the generated-assets folder, keyed by resource path: generator and model, style id, full prompt, source generation id, timestamps, hash of the saved file, and post-processing applied. Invariant: every file in that folder has an entry. The hash detects post-save hand edits (flagged as modified-after-save, not blocked). This is also the store AI-disclosure record. How is a saved asset attributed to AI for audits and store disclosure questionnaires?

Default to vector: the V3 vector model at square aspect for icons - real SVG, crisp at any scale in Godot (ThorVG import). Transparency by stripping the full-canvas background rectangle from the SVG (heuristic validated in M0). Fallback preset: V3 raster at 1024x1024 plus the background-removal endpoint (one cent). Glow is never baked into assets - the style guide mandates flat violet line-art with glow as a halo effect, so glow is applied in-engine (shader or modulate), which also sidesteps alpha-glow generation entirely. gpt-image-1.5 (native transparent background, up to 16 reference images) remains the researched fallback for future painterly card art needing baked alpha. Vector SVG or raster PNG for icons, and how is transparency achieved?

## References
_None._

## Child pages
_None._
