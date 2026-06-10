# Testing plan — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)

**Status:** ready

## Planned
_None._

## Passed
- Headless verify_artgen_service.gd: config golden — models.vector still == 'recraftv3_vector' (existing assertion kept) AND models.vector_v41 == 'recraftv4_1_vector' AND models.raster_v41 == 'recraftv4_1'.
- build_payload v3 regression (byte-identical default path): preset 'icon-flat', no overrides → model 'recraftv3_vector', style_id '19f7542f-0727-4f6f-9d07-728c439fc583' (config default), size '1024x1024', controls and response_format 'b64_json' exactly as today.
- build_payload v4.1 style stripping: preset 'card-glyph' (pins style UUID 89aedef2-…) + opts.model='vector_v41' → payload.model == 'recraftv4_1_vector', NO style_id key, NO negative_prompt key, controls.colors/background_color preserved.
- build_payload explicit-style refusal: opts {preset:'icon-flat', model:'raster_v41', style_id:'89aedef2-…'} → {ok:false, error mentions v3-only styles}; no Recraft API call made.
- build_payload v4 vector size handling: model 'vector_v41' with preset size '1024x1024' (WxH) → size omitted from payload; model 'raster_v41' with '1024x1024' → size kept (valid in the v4.1 ~1MP raster set).
- build_payload identity fallback unchanged: opts.model='recraftv4_1_utility' (not in config map) resolves to itself via config.get('models',{}).get(kind, kind) and gets v4-family capability treatment via the prefix match.
- Dock UI (via godot-ai MCP after editor_reload_plugin): _model_option items are ['preset','vector','raster',…new kinds in deterministic order], repopulated after _open_settings() config reload; selecting a v4.1 kind shows the 'custom styles ignored' note.
- MCP live raster: artgen_generate {preset:'icon-raster', subject:'test sigil', model:'raster_v41', n:1} succeeds; ledger record model=='recraftv4_1'; cost_units ≈ 40 ($0.04 per pricing docs).
- MCP live vector: artgen_generate {preset:'icon-flat', subject:'test sigil', model:'vector_v41', n:1} succeeds with SVG output detected; ledger model=='recraftv4_1_vector'; cost_units ≈ 80 — empirically confirms the v4-vector size-omission rule.
- MCP live error surface: artgen_generate with model:'raster_v41' + style_id:'89aedef2-…' returns a clean {ok:false} pre-flight error through bridge → shim (no opaque Recraft 400).
- Save attribution: artgen_save on a v4.1 generation → game/assets/generated/ai_manifest.json entry has generator=='recraft/recraftv4_1' (or _vector), proving artgen_service.gd:260 needs no change.
- v3 live control: one default icon-flat generation post-change → ledger model=='recraftv3_vector' with the pinned custom style applied, confirming zero behavior drift on the default path.

## Failed
_None._

## References
_None._

## Child pages
_None._
