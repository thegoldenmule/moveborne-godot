# Implementation plan — ArtGen — Recraft Asset Generation

**Status:** ready

## Steps
- [x] M0 spike: curate 3–5 reference crops from art/extracted/ into art/style_refs/ (1024², ≤5 MB total, PNG)
- [x] M0 spike: via curl — POST /v1/styles to create the custom style; generate test icons with style_id vs the named 'Line art' fallback, vector and raster, with controls colors=#A100FF background=black; record costs and outputs under art/generated/
- [x] M0 spike: inspect SVG output for a full-canvas background rect; verify ThorVG import in Godot; decide default preset (vector strip vs raster+removeBackground) and whether the custom style beats the fallback; pin decisions in config.json — exit only when both flagged unknowns from the Spec are resolved
- [x] M1: scaffold game/addons/artgen (plugin.cfg, @tool plugin.gd, bottom-panel registration)
- [x] M1: recraft_client.gd (generate / create_style / list_styles / removeBackground / me; one in-tree HTTPRequest per call, serial queue, 120 s timeout) + multipart.gd (form-data via request_raw)
- [x] M1: artgen_service.gd — presets/config load, request build (style_id XOR style, b64_json, V3 pin), decode + immediate write, post-processing (strip_bg_rect / removeBackground), import validation, ledger append + history_changed/generation_completed signals
- [x] M1: ledger.jsonl fold + in-memory index; thumbnail cache under art/generated/.thumbs/ (gitignored)
- [x] M1: dock UI — compose (preset/subject/variations/advanced), gallery (filters + search), detail view (save / iterate / more variations / discard, black-vs-checkerboard toggle)
- [x] M1: save pipeline — copy to res://assets/generated/<category>/, EditorFileSystem scan + await filesystem_changed, ai_manifest.json upsert, ledger save event
- [x] M1: API key storage (EditorSettings project metadata, RECRAFT_API_KEY env fallback) + settings popup with key validate (GET /v1/users/me) and style management
- [x] M2: bridge.gd — localhost-only TCPServer :4848 (env ARTGEN_BRIDGE_PORT), JSON REST routes mapping 1:1 to the MCP tools, connections held open through 10–60 s generations
- [x] M2: tools/artgen_mcp.ts — zero-dependency Bun stdio MCP shim (initialize / tools list / tools call → bridge REST); clear 'editor not running' error when the port is closed
- [x] M2: register artgen in .mcp.json, enable in .claude/settings.local.json; doc pointers from CLAUDE.md (MCP servers section) and game/CLAUDE.md
- [x] M3 polish (opportunistic): lineage UI, balance display, more presets (card art), optional tools/ manifest-invariant check script, optional headless tools/artgen_cli.gd batch mode

## Data models & interfaces
```jsonc
// art/generated/ledger.jsonl - append-only, one event per line
{"type":"generation","id":"g_<unix>_<hex4>","ts":"ISO-8601Z","provider":"recraft",
 "model":"recraftv3_vector|recraftv3","style_id":"<uuid>|null","style":"<named>|null",
 "preset":"icon-flat|icon-raster|card-glyph|card-illustrated|texture|null",
 "subject":"...","prompt":"<full resolved prompt>","negative_prompt":null,
 "size":"1:1|1024x1024","n":1,"n_index":0,
 "controls":{"colors":[{"rgb":[161,0,255]}],"background_color":{"rgb":[0,0,0]}},
 "random_seed":null,"parent_id":"g_...|null","image_id":"<recraft id>",
 "file":"art/generated/<YYYY-MM>/<id>.<svg|png>","post":["strip_bg_rect|removeBackground"],
 "cost_units":80,"status":"ok|api_error|import_failed"}
{"type":"save","gen_id":"g_...","ts":"...","dest":"res://assets/generated/<cat>/<name>.<ext>","sha256":"..."}
{"type":"discard","gen_id":"g_...","ts":"..."}
{"type":"style_created","ts":"...","style_id":"<uuid>","style":"vector_illustration","refs":["art/style_refs/..."],"cost_units":40}
```

```jsonc
// res://assets/generated/ai_manifest.json - current state of promoted assets
{ "version": 1,
  "assets": { "res://assets/generated/icons/icon_leaderboard.svg": {
      "generator": "recraft/recraftv3_vector", "style_id": "<uuid>",
      "prompt": "<full prompt>", "gen_id": "g_...",
      "generated_at": "...", "saved_at": "...", "sha256": "...",
      "post": ["strip_bg_rect"], "modified_after_save": false } } }

// game/addons/artgen/config.json - committed pins
{ "style_id": "<uuid>|null", "fallback_style": "Line art",
  "models": { "vector": "recraftv3_vector", "raster": "recraftv3" },
  "bridge_port": 4848 }
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
