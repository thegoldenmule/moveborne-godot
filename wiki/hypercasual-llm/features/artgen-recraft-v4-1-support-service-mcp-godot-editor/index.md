# Feature: ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)

**Status:** building

## Summary
Add opt-in Recraft v4.1 generation to the shipped ArtGen pipeline while keeping v3 (and its two load-bearing custom styles) the default at every layer. Web research against the official Recraft docs confirms v4.1 exists (released 2026-05-14, now the API default) with two facts that reshape the naive plan: (1) the real model identifiers use underscores — recraftv4_1 / recraftv4_1_vector — never 'recraftv4.1'; and (2) every v4-family variant REJECTS style/style_id and negative_prompt (custom styles are v2/v3-only per the styles docs), supports only controls.colors/background_color, and v4-family vector models take aspect-ratio sizes rather than WxH. The repo already separates model KIND from model ID via the config.json models dict (resolved at artgen_service.gd:119 with identity fallback), and recraft_client.gd/bridge.gd are pure passthroughs, so the work is: add vector_v41/raster_v41 kinds to config.json; teach artgen_service.gd model-family capabilities via an extracted, headlessly-testable build_payload() helper that strips/refuses style_id + negative_prompt and fixes size handling for v4 vector; make the dock.gd model dropdown config-driven instead of the hardcoded ['preset','vector','raster']; update the artgen_mcp.ts model param docs; extend the golden assertions in game/tools/verify_artgen_service.gd; then live-smoke one v4.1 raster + one v4.1 vector generation through the MCP and confirm ledger model and ai_manifest generator fields record recraftv4_1* automatically (no schema change). The v3 default path must remain byte-identical.

## Components affected
- game/addons/artgen/config.json — models kind→ID map (add vector_v41/raster_v41; keep v3 kinds + style_id untouched)
- game/addons/artgen/artgen_service.gd — MODEL_CAPS family-capability table + extracted build_payload() with v4-family sanitization (rest of generate() unchanged)
- game/addons/artgen/dock.gd — config-driven model dropdown (replaces hardcoded list at 141-143) + v4.1 style-loss note; _on_generate contract unchanged
- tools/artgen_mcp.ts — artgen_generate model param schema/description update (line 46); routing untouched
- game/addons/artgen/bridge.gd + recraft_client.gd — verified no-change (pure passthroughs)
- game/addons/artgen/presets.json — no change (all presets stay v3; v4.1 reached via model override)
- game/tools/verify_artgen_service.gd — extended golden assertions + new build_payload tests
- art/generated/ledger.jsonl + game/assets/generated/ai_manifest.json — no schema change; new records carry recraftv4_1* model/generator values

## Design constraints
1. Naming: the real API identifiers are recraftv4_1 / recraftv4_1_vector (underscore point-release convention) — never 'recraftv4.1'; OpenRouter's 'recraft/recraft-v4.1' is a gateway slug, not the API id. A dot-form id would silently 400.
2. v4/v4.1 reject style and style_id outright; custom styles created via /v1/styles are 'compatible with Recraft V3 and Recraft V3 Vector models only' — the two account styles (89aedef2-…, 19f7542f-…) pinned in presets.json/config.json CANNOT be used with or recreated for v4.1.
3. v4/v4.1 drop negative_prompt (v2/v3-only) and text_layout (v3-only); controls is partial — controls.colors and controls.background_color work on all models, artistic_level/no_text are v3-only (presets only use colors/background_color, so they survive).
4. Size semantics differ by family: v2/v3 use the classic WxH list; v4-family standard rasters use a ~1MP WxH set including 1024x1024; v4-family VECTOR models take aspect-ratio sizes ('1:1', '2:1', …) and auto-select when size is omitted — the service must not send WxH to a v4 vector model.
5. Recraft's API default model is now recraftv4_1 — the service must keep sending an explicit model on every request (it does at artgen_service.gd:119/125), or omitted-model requests would silently move to v4.1 and reject style_id-bearing payloads.
6. Keep v3 the default everywhere: 'vector'/'raster' kinds, all preset model fields, and config style_id stay as-is; v4.1 is opt-in via the new kinds. The shipped occult-arcade look depends on the v3 custom styles. The v3 default payload must remain byte-identical.
7. Pricing/limits for smoke-test budgeting: recraftv4_1 raster $0.04/img, recraftv4_1_vector $0.08 (both same as v3 equivalents); Pro tiers $0.25/$0.30; 100 images/min + 5 req/s; prompt cap rises to 10k chars on v4.x (vs 1k on v3).
8. Image-input endpoints (image-to-image, inpaint, outpaint, background ops) remain recraftv3/recraftv3_vector-only in the official API — rules out any v4.1 img2img ambition in this pipeline.
9. Repo conventions: commit directly to main; edit wiki content only through the wiki MCP (on-disk wiki/*.md mirror is emitter-owned); after editing .gd files, filesystem_manage reimport before editor test runs; the Godot editor must be open with the ArtGen plugin enabled for any MCP-shim live test.
10. Verification caveat: Recraft's machine-readable swagger was unreachable (404); all v4.1 parameter claims come from the human-readable official docs — the live smoke test doubles as empirical confirmation of the style/size rules.

## Open questions
1. **Which v4.1 variants to expose as named kinds? The family has 8 models; this plan pins only the base pair (recraftv4_1, recraftv4_1_vector). The Utility line ('clean, simple, predictable' — pitched for icons, same $0.04 price) looks tailor-made for this project's icon presets; Pro is 6–7x cost. Default taken: base pair only — Utility/Pro remain reachable via the identity fallback (pass the raw model id as the kind). Add raster_v41_utility/vector_v41_utility as named kinds now, or later?**
2. **Strictness of the style guard: the implementation errors on EXPLICIT opts.style_id + v4.1, and silently strips preset/config-INHERITED style_ids (recording style_id null in the ledger). Acceptable, or should preset-inherited style stripping also hard-fail (forcing users to pick a style-free preset for v4.1)?**
3. **Should any v4.1-native presets be added (e.g. 'icon-flat-v41' with a prompt retuned to compensate for the lost custom style)? Without the v3 styles, v4.1 output will diverge from the established occult-arcade look — this is an art-direction decision (art/STYLE_GUIDE.md), not an engineering one. Out of scope for this feature unless requested.**
4. **Config kind naming is committed surface area (config.json keys appear in dock UI, MCP docs, and muscle memory): default taken is 'vector_v41'/'raster_v41' (matches existing 'vector'/'raster' with a version suffix). OK, or prefer 'v41_vector'/'v41_raster' or a structured scheme?**

## Resolved questions
1. **Should any preset default eventually flip to v4.1 (better short-prompt adherence, 10k-char prompts) despite losing custom styles? Recommend revisiting only after a side-by-side output comparison; defaulting now would silently change the game's shipped art style. Not part of this feature.** — _Decided by the user 2026-06-10: ALL presets now default to v4.1 (commit 085f0bb) — model kinds vector_v41/raster_v41 in presets.json. v3 + custom styles remain reachable via the per-generation model override ('vector'/'raster'). Dock Load resolves the style field to 'none' on style-less models so Load→Generate can't trip the explicit-style refusal. Verified live: default icon-flat lands on recraftv4_1_vector._

## References
_None._

## Child pages
- [Implementation plan — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)](implementation-plan:mq88pnku-000x-77nvic)
- [Testing plan — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)](testing-plan:mq88pnku-000y-7jmitx)
- [Spec — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)](feature-spec:mq88pnkv-000z-ix8ln1)

## Commits
- `4af03d85b55be3ef8a3708d45310702de2c9f30b` feat(artgen): Recraft v4.1 support at all layers (service, MCP, dock)
- `6cca9c3e2f0cc3c33f6caac1893202831aa14247` fix(artgen): code-review hardening for the v4.1 pass
