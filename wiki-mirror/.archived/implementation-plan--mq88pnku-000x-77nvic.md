# Implementation plan — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)

**Status:** ready

## Steps
- [x] config.json (game/addons/artgen/config.json): extend the models dict additively — keep vector: recraftv3_vector and raster: recraftv3 untouched, add vector_v41: recraftv4_1_vector and raster_v41: recraftv4_1 (underscore identifiers verbatim from the Recraft endpoints docs). Do NOT change config style_id or any presets.json model field.
- [x] artgen_service.gd: add a MODEL_CAPS capability table (family-prefix keyed: recraftv4 family → supports_styles=false, supports_negative_prompt=false, vector_size_is_aspect_ratio=true; recraftv3/recraftv2 → current behavior) near the top of the script, sourced from the official endpoints/appendix/styles docs.
- [x] artgen_service.gd: extract the payload construction in generate() (model_kind resolution, model lookup via config.get('models',{}).get(model_kind, model_kind), size, style_id cascade opts→preset→config, controls, negative_prompt) into func build_payload(opts: Dictionary) -> Dictionary returning either the Recraft request body or {ok:false, error:…}. generate() calls it; ledger event, balance/cost logic, and save flow unchanged.
- [x] build_payload v4-family rules: (a) explicit opts.style_id (other than 'none') on a v4-family model → {ok:false, error mentions styles are v3-only} before any API call; (b) preset/config-inherited style_id → silently omitted (ledger records style_id null via existing payload.get('style_id')); (c) always drop negative_prompt for v4-family; (d) keep controls (colors/background_color supported on all models); (e) for v4-family _vector models omit the size field when it matches a WxH pixel pattern (Recraft auto-selects; v4 vector sizes are aspect-ratio strings).
- [x] dock.gd: replace the hardcoded for kind in ['preset','vector','raster'] loop (lines 141-143) with a _populate_models() helper — 'preset' first, then service.config.get('models', {}).keys() stable-sorted so v3 kinds keep their positions; also call it from _open_settings() after service.reload_config() so config edits refresh the dropdown. The _on_generate() contract (pass item text as opts['model'] when selected > 0) stays unchanged.
- [x] dock.gd UX guard: when the selected model kind resolves to a v4-family model, surface a one-line note ('v4.1: custom styles ignored') in/near the model row so users understand why styled presets lose the pinned style. The read-only model field in the detail pane already shows the resolved ID from the ledger record — no change.
- [x] tools/artgen_mcp.ts: update the model param description (line 46) from "'vector' | 'raster' override (optional)" to document the config-driven kinds incl. v4.1 restrictions (style_id/negative_prompt rejected by the API and stripped/refused by the service); extend the artgen_generate tool description with the same caveat. No routing change — args pass verbatim to bridge POST /generate.
- [x] bridge.gd and recraft_client.gd: verify no change needed (both pure passthroughs — bridge forwards the body verbatim to service.generate(); recraft_client POSTs the payload to /v1/images/generations unchanged). Confirm the service always sends an explicit model (artgen_service.gd:119/125) so no request can silently drift to Recraft's new v4.1 API default.
- [x] game/tools/verify_artgen_service.gd: extend (don't replace) the golden config check — keep models.vector == 'recraftv3_vector', add models.vector_v41 == 'recraftv4_1_vector' and models.raster_v41 == 'recraftv4_1'. Add build_payload() assertions: v3 default path byte-identical to today; v4.1 kind strips inherited style_id + negative_prompt and omits WxH size for vector_v41; explicit style_id + v4.1 → ok=false with no API call; identity fallback gives v4-family treatment to raw ids like recraftv4_1_utility.
- [x] Reimport + run: filesystem_manage reimport the changed .gd paths, run the headless verifier (Godot --headless --path game --script res://tools/verify_artgen_service.gd → PASS), then editor_reload_plugin for ArtGen and confirm the dock dropdown shows the new kinds.
- [x] Live smoke test through the MCP shim (Godot editor open, bridge on :4848): (a) artgen_generate raster_v41 → ledger model recraftv4_1; (b) artgen_generate vector_v41 → SVG output, ledger model recraftv4_1_vector (confirms size-omission behavior); (c) artgen_save one result → ai_manifest generator 'recraft/recraftv4_1*' with no code change; (d) one v3 control generation to prove the default path unchanged; (e) explicit style_id + v4.1 → clean pre-flight error through bridge→shim.
- [x] Commit directly to main (repo convention): config.json, artgen_service.gd, dock.gd, artgen_mcp.ts, verify_artgen_service.gd, plus any smoke-test ledger/manifest/asset changes; recordCommit on the brief with the real sha.

## Data models & interfaces
```json
// game/addons/artgen/config.json — extended models map (additive; v3 kinds unchanged)
{
	"style_id": "19f7542f-0727-4f6f-9d07-728c439fc583",
	"fallback_style": "Line art",
	"models": {
		"vector": "recraftv3_vector",
		"raster": "recraftv3",
		"vector_v41": "recraftv4_1_vector",
		"raster_v41": "recraftv4_1"
	},
	"bridge_port": 4848
}
```

```gdscript
# game/addons/artgen/artgen_service.gd — model-family capability table + extracted payload builder.
# Facts per https://www.recraft.ai/docs (endpoints / appendix / styles):
# every v4/v4.1 variant rejects style/style_id and negative_prompt; only
# controls.colors + controls.background_color work on all models; v4-family
# vector models take aspect-ratio sizes (omit size -> Recraft auto-selects).
const MODEL_CAPS := {
	"recraftv4": {  # prefix match covers recraftv4_1, *_pro, *_utility, *_vector
		"supports_styles": false,
		"supports_negative_prompt": false,
		"vector_size_is_aspect_ratio": true,
	},
	# default (recraftv3 / recraftv2 families): current behavior, styles + negative_prompt OK
}

## Pure payload construction extracted from generate().
## Returns the Recraft /v1/images/generations body, or {"ok": false, "error": ...}
## when the request is invalid for the resolved model (e.g. explicit style_id on v4.1).
func build_payload(opts: Dictionary) -> Dictionary:
	# model_kind := opts.model | preset.model | "vector"
	# model      := config.models.get(model_kind, model_kind)   # identity fallback kept
	# payload    := {prompt, model, n, size?, response_format: "b64_json",
	#                style_id?, controls?, negative_prompt?}
	# v4-family: drop preset/config style_id (error if opts.style_id explicit),
	#            drop negative_prompt, omit WxH size for *_vector models.
	pass
```

```typescript
// tools/artgen_mcp.ts — artgen_generate model param, updated description only;
// routing stays a verbatim passthrough to bridge POST /generate.
model: {
  type: "string",
  description:
    "model kind from config.json models map: 'vector' | 'raster' (Recraft v3, " +
    "supports custom styles) | 'vector_v41' | 'raster_v41' (Recraft v4.1 — " +
    "style_id/negative_prompt rejected by the API and stripped by the service) (optional)",
},
```

```json
// art/generated/ledger.jsonl generation event — shape UNCHANGED (forward-compatible).
// The ledger journals the SENT payload fields: for v4.1 runs 'model' carries the
// recraftv4_1* id, 'style_id' is null (stripped — v3-only), and for v4 VECTOR runs
// 'size' is null too (WxH omitted; the API auto-selects). ai_manifest.json
// 'generator' becomes "recraft/recraftv4_1*" automatically via artgen_service.gd save.
// Verified live 2026-06-10 (g_1781107690_325c):
{
  "type": "generation", "id": "g_1781107690_325c", "ts": "2026-06-10T16:08:10Z",
  "provider": "recraft",
  "model": "recraftv4_1_vector",
  "style_id": null,
  "preset": "icon-flat", "subject": "test sigil", "prompt": "...",
  "negative_prompt": null, "size": null, "n": 1, "n_index": 0,
  "controls": { "colors": [{ "rgb": [161, 0, 255] }], "background_color": { "rgb": [0, 0, 0] } },
  "random_seed": null, "parent_id": null, "image_id": "739b73fb-d33a-4295-8048-20028b49898e",
  "file": "art/generated/2026-06/g_1781107690_325c-test-sigil.svg", "post": ["strip_bg_rect"],
  "cost_units": 80, "status": "ok"
}
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
