# Spec — ArtGen — Recraft v4.1 Support (service, MCP, Godot editor)

**Status:** sealed

## Overview
Opt-in Recraft v4.1 generation across the whole ArtGen pipeline — editor service, MCP shim, and dock — later flipped to the DEFAULT for all presets by user decision. The real API identifiers are recraftv4_1 / recraftv4_1_vector (underscores). The v4 family rejects style/style_id (custom styles are v2/v3-only) and negative_prompt, and v4 vector models take aspect-ratio sizes; the service sanitizes payloads accordingly. v3 and the two custom occult-arcade styles remain reachable per-generation via the model override ('vector'/'raster'). Shipped 2026-06-10 in commits 4af03d8 (feature), 6cca9c3 (review hardening), 085f0bb (v4.1 preset defaults).

## Design
## Design

The config models map gained two v4.1 kinds alongside the untouched v3 kinds; the existing kind-to-id indirection (with identity fallback for raw model ids) is the only registration point, and the dock dropdown and MCP docs are config-driven from it.

```text
config.json models: vector -> recraftv3_vector, raster -> recraftv3,
                    vector_v41 -> recraftv4_1_vector, raster_v41 -> recraftv4_1
MODEL_CAPS (prefix "recraftv4", longest match wins):
  supports_styles=false, supports_negative_prompt=false,
  vector_size_is_aspect_ratio=true
build_payload(): explicit style_id + v4.x -> {ok:false} pre-flight;
  inherited style_id / negative_prompt stripped (ledger records null);
  WxH size omitted for v4 *_vector models (API auto-selects)
```

The service owns the family rules via a prefix-keyed capability table consumed by a pure, headlessly-testable payload builder. The bridge and Recraft client stayed pure passthroughs; the ledger and manifest needed no schema change since generator attribution flows from the resolved model id.

Verification: the headless service verifier asserts the config golden, the v4 sanitization rules, and a byte-identical v3 payload (pinned via an explicit model kind after the default flip); the editor dock suite toggles the live plugin and asserts the config-driven dropdown and style-loss note; live smoke runs confirmed v4.1 raster and vector generation, the pre-flight style refusal through the bridge and MCP, manifest attribution, and an unchanged v3 control.

## Decisions
Kind naming: version-suffixed kind names (the v41 suffix on the existing vector/raster names); shipped across config, dock, and MCP docs and in active use. Config kind naming is committed surface area (config.json keys appear in dock UI, MCP docs, and muscle memory): default taken is 'vector_v41'/'raster_v41' (matches existing 'vector'/'raster' with a version suffix). OK, or prefer 'v41_vector'/'v41_raster' or a structured scheme?

Expose only the base v4.1 pair as named kinds. Utility and Pro variants remain reachable by passing the raw Recraft model id (identity fallback plus v4-prefix capability match); adding named kinds is a config-only change. Which v4.1 variants to expose as named kinds? The family has 8 models; this plan pins only the base pair (recraftv4_1, recraftv4_1_vector). The Utility line ('clean, simple, predictable' — pitched for icons, same $0.04 price) looks tailor-made for this project's icon presets; Pro is 6–7x cost. Default taken: base pair only — Utility/Pro remain reachable via the identity fallback (pass the raw model id as the kind). Add raster_v41_utility/vector_v41_utility as named kinds now, or later?

Style guard strictness: hard-fail only on an explicit style id with a v4.x model; silently strip inherited preset/config styles. Dock Load resolves the style field to 'none' on style-less models so the Load-then-Generate path cannot trip the refusal. Strictness of the style guard: the implementation errors on EXPLICIT opts.style_id + v4.1, and silently strips preset/config-INHERITED style_ids (recording style_id null in the ledger). Acceptable, or should preset-inherited style stripping also hard-fail (forcing users to pick a style-free preset for v4.1)?

Preset defaults: the user flipped ALL presets to v4.1 (commit 085f0bb). v3 plus the custom styles stay one model override away; preset style pins are kept as documentation and for the v3 path. Should any preset default eventually flip to v4.1 (better short-prompt adherence, 10k-char prompts) despite losing custom styles? Recommend revisiting only after a side-by-side output comparison; defaulting now would silently change the game's shipped art style. Not part of this feature.

No v4.1-native presets for now; existing prompts carried over with the default flip. Prompt retuning to compensate for the lost custom styles is deferred art-direction work if output drifts from the occult-arcade look. Should any v4.1-native presets be added (e.g. 'icon-flat-v41' with a prompt retuned to compensate for the lost custom style)? Without the v3 styles, v4.1 output will diverge from the established occult-arcade look — this is an art-direction decision (art/STYLE_GUIDE.md), not an engineering one. Out of scope for this feature unless requested.

## References
_None._

## Child pages
_None._
