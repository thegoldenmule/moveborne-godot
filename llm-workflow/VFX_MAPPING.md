# Moveborne VFX → Godot 4.6 Mapping

The engineering reference for porting Moveborne's web-client polish (PixiJS 8 + revolt-fx
+ pixi-filters) to the Godot 4.6 (GDScript) port. Companion to `GODOT_PORT_PLAN.md`.

**Prime directive (repeated where it bites):** all VFX live in `scenes/` (presentation),
react to `MbMatch` state, and **never write back into `engine/`**. Determinism parity is
load-bearing — VFX state (tweens, shake offsets, particle counts) must never feed into the
hashed engine state. The TS source of truth is `~/projects/thegoldenmule/moveborne/src/game`
(client VFX) and `.../src/logic/src` (synchronized state).

---

## 1. TL;DR — the stack and what replaces it

Moveborne's VFX ride on **four** subsystems, not one:

| Web subsystem | What it does | Godot replacement |
|---|---|---|
| **revolt-fx** (single `FX()`, ticked per frame) | GPU sprite-particle emitters from a JSON bundle (`custom-1/effects.json` + `texture.json`). ~16 live emitters, one-shot by name at a pixel x/y. | `GPUParticles2D` one-shots (`one_shot=true`, `explosiveness=1.0`) pooled under an FX `Node2D`, driven by a `const EMITTERS` table mirroring the JSON. Streak particles need a custom particle `.gdshader`. |
| **pixi-filters** (`GlowFilter`, `TwistFilter`, `GlitchFilter`) cached in `FilterCache` | Per-object glow on tile numbers/cards/HUD; animated twist on black-hole overlay; one full-screen glitch. | Per-node `ShaderMaterial` (outline-glow + twist `.gdshader`); screen-read `.gdshader` on a top `CanvasLayer` `ColorRect` for glitch. Godot resources are ref-shared = the `FilterCache` for free. |
| **Custom tween engine** (`ease.ts` + `tweens.ts` + RAF loop) | Hand-rolled `ease()` builder + 13 curves. Drives doober, floating text, shake, flash, card juice, combo pop. | `create_tween()` (**seconds not ms**); `tween_method` for the `{t:0}`+onUpdate pattern. No manager port needed. |
| **Raw `requestAnimationFrame` loops** (bypass the tween engine) | Countdown intro, HUD banner, totem tooltip, selection pulse — fixed per-frame increments (`alpha += 0.05/frame`), **frame-rate dependent**. | Route through a central `Anim` helper as time-based `create_tween()`/`_process(delta)` — **do not** copy the per-frame increments literally (wrong speed off-60fps). |

Plus a few **procedural-graphics** effects (doober diamond, shard pills, floating text) with
**no asset dependency** that port 1:1 to `Polygon2D`/`Line2D`/`Label`.

**The 5 Godot building blocks:**
1. **`Vfx` autoload + FX `Node2D` layer** — `createEffect(name, world_pos)` dispatcher + pool.
2. **`GPUParticles2D` presets** — one "pop" preset covers 7 emitters; streak/run need a `.gdshader`.
3. **`VfxMaterials` cache** — string-keyed shared `ShaderMaterial` (glow/twist); the `FilterCache` analogue.
4. **`Anim` helper + `create_tween()` chains** — doober/floating-text/flash/shake/card juice; the central home for the ex-RAF loops too.
5. **`Quality` autoload** (LOW/MEDIUM/HIGH) gating glow strength, persisted via `ConfigFile`.

**Brand colors:** primary purple `0xb400ff` → `Color(0.706, 0.0, 1.0)`; freeze blue `0x406EBB`;
amplify gold `0xFEDC56`/`0xffd700`; doober cyan `0x00ffff`.

---

## 2. Decisions (resolved)

These were open questions; resolved against the source and the developer's direction.

1. **Trigger source — authoritative `status`, confirmed.** The synchronized state
   (`logic/src/types.ts:103` `SynchronizedTileState.status`, top-level `moveIndex`) carries
   per-tile `status` (full 18-value `TileStatus` union) and `moveIndex`. The Godot port mirrors
   both byte-for-byte — `engine.gd` sets `status` (`"new"`, `"merged"`, … `engine.gd:108/245`,
   `powercards.gd`) and bumps `moveIndex` (`engine.gd:443/454/463`, `match_controller.gd`).
   `board_view.render(state)` already receives `state` but today only reads `value`/`isEmpty`
   (`board_view.gd:80-87`) — it just needs to start reading `status` and tracking `moveIndex`.
   **→ drive all VFX from status-diffing in `board_view`, gated on `moveIndex`. No value-diff heuristic.**
2. **Full-screen glitch needs an engine task first.** `engine.gd:293 _process_global_effects`
   is a confirmed stub (returns state unchanged even when `globalEffects` is non-empty).
   **Completing it is part of the plan** (P10a): port `globalEffects.ts processGlobalEffects`
   — decrement `movesRemaining`, reseed, ramp `offset`, drop at 0 — and **re-verify against a
   golden** (it mutates hashed state, so it's a determinism-parity task).
3. **Glow = per-node shader.** Per-`Label`/`TextureRect` outline-glow `.gdshader`, controllable,
   no screen bloom. WorldEnvironment 2D glow is **not** used (global, blooms bright UI).
4. **Fonts are present.** `fonts/Grammara-Normal.woff2` is imported (HUD / countdown / destroy-text).
   Floating text's Arial → project default/system font. No font work needed.
5. **HUD must be built.** The `scenes/` HUD doesn't exist yet. **Building it is part of the plan**
   (P0b): a `HudLayer` `CanvasLayer` with score/timer/combo labels, shard counter + a `Marker2D`
   doober target, skull displays. Prerequisite for doober target, floating text, combo pop, HUD glow.
6. **Easing: close enough.** Use `TRANS_BACK`/`TRANS_ELASTIC`; do not port the web's exact
   overshoot/elastic constants. `cubic`/`bounce`/`linear` are identical to built-ins anyway.
7. **Ex-RAF loops route through the central system.** The countdown, HUD banner, totem tooltip,
   and selection-overlay pulse use raw `requestAnimationFrame` per-frame increments in the web
   client. Port them through a central `Anim` helper as **time-based** `create_tween()` chains
   (not literal per-frame increments), so all animation lives in one place.

**Assets already in the port** (verified): `assets/fx/frames/*.png` (incl. `lock-2.png`, `plus`,
`x`, `snowflake`, `stone`, `deck-symbol` — the live frames, already individual PNGs, **so no
spritesheet slicing is required**), `assets/fx/bundles/custom-1/{effects,texture}.json`,
`assets/tile-effects/{freeze,stone,lock,black-hole,amplify}/` overlays.

---

## 3. VFX inventory

Durations from revolt-fx JSON are in **seconds** → map straight to `GPUParticles2D.lifetime`.
Tween durations are in **ms** → divide by 1000. `blendMode 1 = ADD`, `0 = NORMAL`.

### A. Sprite particles (revolt-fx, `custom-1` bundle)

| Effect | Trigger | Pixi impl | Key params | Godot mapping | Effort |
|---|---|---|---|---|---|
| **new-tile** (spawn pop) | `status=='new'` & new move (board.ts:622) | emitter id0, 5× `plus.png`, ADD, no motion | count 5, life 0.01–0.5s, alpha 0.7→0, tint `0xB400FF`, scale 0.1→1..3 easeInCubic, box point | "pop" preset, emission POINT, amount 5, lifetime 0.5, **scale_max=3** + ramp curve | low |
| **merge** (radial streak burst) | `status=='merged'` & new move (board.ts:643) | emitter id26, 20× `plus.png`, radial box 10×200 rot −90° | count 20, life 0.01–0.25s, dist 10–150 easeOutExpo, alpha 0.1–0.5→0, tint `0xB400FF`, **scaleX 0.5→2 / scaleY 0.1→0.2** | GPUParticles2D + **streak `.gdshader`** (anisotropic) | high |
| **delete** (tile destroyed) | `status=='destroyed'` (board.ts:550) | emitter id4, 4–10× `x.png`, circle r70 | count 4–10, moveSpeed 1–10, life 0.1–0.4s, scale 0.1→0.5..2, tint `0xB400FF`, ADD | disc r70, scale_max=2 | medium |
| **bomb-explode** | `status=='bombed'` (board.ts:529) | emitter id7, 6–12× `plus.png`, circle r70 | count 6–12, life 0.1–0.6s, scale 0.1→0.5..2, ADD | disc r70 | medium |
| **purge-column** | `status=='purged'`, once/column (board.ts:572) | emitter id10, 20× `plus.png` streak, box 10×200 | dist 10–150 easeOutExpo, scaleX 0.5→2 / scaleY 0.1→0.2 | streak shader, at column center (row 1.5) | high |
| **black-hole spawn/run/removal/consume** | tile-effect lifecycle (tile-display.ts:413/440/465) + consume on 400ms suck (engine.ts:665) | ids 17/18/6/9, `x.png` | run: infinite box 70×70, dist 1–3, scaleX 0.5→2; consume: 4–10 circle r70 | spawn/removal=pop; run=looping streak (`emitting` toggled by lifecycle); consume=disc | medium |
| **freeze spawn/run/removal** | tile-effect 'freeze' | ids 14/16/15, `snowflake.png`, tint `0x406EBB` | run: **NORMAL blend**, alpha 0.8–1; removal: 10–30 gravity 0.35 | pop(blue)+streak(NORMAL)+gravity burst | medium |
| **amplify spawn/run/removal** | tile-effect 'amplify'/'amplify_static' | ids 19/13/20, `plus.png`, run tint `0xFEDC56` gold | run: infinite streak; removal: 10–30 gravity | gold pop+streak+gravity burst | medium |
| **lock spawn/removal** | tile-effect 'lock' | ids 22/21, **`lock-2.png`**, removal gravity | spawn 5 pop; removal 10–30 gravity 0.35 | pop+gravity burst, `lock-2.png` frame | low |
| **stone spawn/removal** | tile-effect 'stone' | ids 23/24, `stone.png`, **NORMAL blend, no tint** | removal 5–10, useRotation (rotSpeed 0–0.0349 rad), gravity, scale 0.3–0.4 | pop+gravity burst w/ `angular_velocity`, NORMAL, native color | low |
| **deck-ready** | deck becomes ready (deck-display.ts:124) | emitter id12, 5× `deck-symbol.png`, ADD purple | count 5, scale 0.1→1..3 easeInCubic | pop preset, `deck-symbol.png` | low |
| **decay-spawn / decay-removal** | factories wire them but **emitters don't exist** | — | — | **DEAD — skip.** Port uses border `#6b8e23` | n/a |
| **amplify-consume / splosion / merge-horizontal / merge SEQUENCE** | referenced/defined but never invoked or missing | — | — | **DEAD — skip.** | n/a |

**Frame assignment:** `plus.png` → merge/purge/new-tile/bomb/amplify; `x.png` → delete/black-hole-*;
`snowflake.png` → freeze-*; `stone.png` → stone-*; **`lock-2.png` → lock-***; `deck-symbol.png` →
deck-ready. The unused frames in `texture.json` (`amplify/black-hole/freeze/lock/energy/skull/square_*`)
are legacy — ignore. `displacement.png` is a **red herring** (black hole uses *twist*, not displacement).

### B. Per-object filters/shaders

| Effect | Trigger | Pixi impl | Key params | Godot mapping | Effort |
|---|---|---|---|---|---|
| **Tile value-text glow** | every `TileDisplay.render`, glow style + GLOW enabled | `GlowFilter` on value Text only | 2/4: none; 8–64: white d8 s1; 128: white d12; **256+: purple `0xb400ff` d15 s2**; quality 0.1/0.3 | per-`Label` outline-glow `.gdshader`, value→params dict mirroring `TileValueStyles` | medium |
| **Power-card glow** | card render | shared `GlowFilter` on card container | purple `0xb400ff`, d20, s2 | shared outline-glow material (ref-shared = cache) | low |
| **Disabled card dim** | `isDisabled` | sprite `tint=0x666666`, `alpha=0.6` (NOT a filter) | — | `self_modulate = Color('666666', 0.6)` on art node only | low |
| **HUD value glow** | HUD ctor | `GlowFilter` white d10 s1 | — | outline-glow material on value `Label` | low |
| **black-hole overlay twist** | `effect.type=='black_hole'` & HIGH | animated `TwistFilter` | radius 70, `angle = sin(time*0.02)*1` (**per-frame ~60×**), offset 70/70 | twist `.gdshader`, **`angle = sin(time_sec*1.2)`** (frame→sec), HIGH-only, **per-instance** | medium |
| **Tile-effect overlays** | effect active, `overlayTexture` present | centered overlay `Sprite` | freeze/black_hole 100px, stone/amplify 78px, lock 70px; scale `tile_px/70` | `TextureRect` (assets/tile-effects/*) | low |
| **amplify bg + multiplier** | effect active, `backgroundTexture`/`showMultiplier` | bg sprite under value + gold `Nx` label | bg 78px; mult `0xffd700`, 2px black stroke, bottom-right | `TextureRect` (z below value) + `Label` w/ `outline_size=2` | low |

### C. Screenshake & impact

| Effect | Trigger | Pixi impl | Key params | Godot mapping | Effort |
|---|---|---|---|---|---|
| **Merge screenshake** (the *only* shake) | once/move when `totalMergeValue>0` (board.ts:677) | offsets **entire stage**, random per-frame jitter, cubicOut decay | `intensity = min(5 + value/32*0.5, 20)`, **200ms** fixed, amp `intensity*(1 - cubicOut(t))` | `_process`+`randf()` on root `Control.position` (Camera2D is a no-op in this Control-based port); not a single Tween (needs fresh random/frame) | low |

### D. Tween-driven UI & collectibles

| Effect | Trigger | Pixi impl | Key params | Godot mapping | Effort |
|---|---|---|---|---|---|
| **Doober** (shard fly) | `SHARD_EARNED`, one per merged tile (engine.ts:515) | cyan diamond Graphics, 4-phase chain | fade-in 100ms; fly x cubicInOut + y cubicOut 600ms (arc from **different x/y eases**); pulse 1→1.3→1; pop 1→2 backOut + fade 200ms | `Node2D` + `Polygon2D`+`Line2D`; **two parallel `position:x`/`position:y` tweens** under `.set_parallel(true)`; callback unlocks shard counter | medium |
| **Floating score text** | merges (input.ts:789), card effects, tile destroy (engine.ts:675) | bold `Text` rise+fade | rise `distance` cubicOut over `duration`; fade linear over `duration/2` delayed `duration/2`; defaults 24px/1000ms/50px; common 20px/1500ms/30px; `direction` **unused** | `Label`+`LabelSettings(outline_size=4)`, parallel `position:y` + delayed `modulate:a` | low |
| **Combo multiplier pop** | `COMBO_MULTIPLIER_CHANGED` increased (engine.ts:508) | elastic scale punch | 1.0→1.6 over 300ms elasticOut, then 1.6→1.0 over 500ms cubicOut; flag-guarded | chained tween, `pivot_offset=size/2`, TRANS_ELASTIC→TRANS_CUBIC | low |
| **Card flip** | card detail toggle (maybe unused in port) | `scale.x = cos(t*PI)`, face swap at t≥0.5 | 300ms cubicInOut | `tween_method` computing `cos(t*PI)` | low |
| **Card focus wiggle** | `setFocused(true)` | elastic scale + skew | 400ms elasticOut, scale→1.1, skew x 0.2/y 0.1 | `Node2D` (has `skew`) + tween_method; independent x/y skew needs `transform` | medium |
| **Card description panel** | focus | slide+fade | show 250ms cubicOut, hide 200ms cubicIn, y±20 | Panel + parallel `modulate:a` + `position:y` | low |
| **Skull blast** | event-trigger status→'triggered' (skull-display.ts:315) | overlay sprite scale 1→1.8 + fade, 600ms cubicOut | base swap idle↔primed is **instant** | `Sprite2D` + parallel scale/`modulate:a`, `queue_free` callback | medium |
| **black-hole destroy fly** (only true positional tile tween) | `TILE_DESTROYED` w/ target | throwaway `Text` flown to black hole, scale→0, 400ms cubicIn | Grammara 42px white, 4px stroke | temp `Label`, parallel pos+scale TRANS_CUBIC EASE_IN, then consume burst + red `-value` float | medium |

### E. Full-screen / global

| Effect | Trigger | Pixi impl | Key params | Godot mapping | Effort |
|---|---|---|---|---|---|
| **Screen glitch** (the only global filter) | scenario 17 "Fracture" on COMBO_BREAK minCombo 3 | `GlitchFilter` on whole `filterRoot` | slices 10, offset 5 init then **15–25 ramp/move**, seed reseeded/move, direction 0°, duration **10 moves** (move-quantized) | top `CanvasLayer` `ColorRect` + glitch `.gdshader` (`hint_screen_texture`); read `filterConfig` live each frame. **Blocked on engine task (§2.2)** | medium |
| **Countdown intro** (3-2-1-GO!) | game start (engine.ts:744) | RAF: black overlay alpha→0.7, Grammara 120px number pulses scale 1.5→1/count, GO! at scale 2 then grow+fade | per-frame increments (frame-dependent) | `CanvasLayer`+`Label`+3 `create_tween` chains, via `Anim` | low |
| **HUD message banner** ("Let's Play!") | post-countdown (engine.ts:760) | RAF centered `Text` fade-in/hold/fade-out | duration 1000, fontSize 48 | `CanvasLayer` `Label`, fade-in→`tween_interval`→fade-out, via `Anim` | low |
| **Selection-overlay idle pulse** | power-card selection mode | **raw RAF** alpha 0.3↔1.0 at 0.02/frame | green `0x44ff88`, outline width 3 alpha 0.8 | looping `create_tween` on `modulate:a` ~0.35s/half-cycle (time-based), via `Anim` | low |

---

## 4. Godot VFX architecture (keep `engine/` pure)

**Trigger source (resolved §2.1):** `board_view.gd` diffs per-tile `status`
(`new`/`merged`/`bombed`/`destroyed`/`purged`/`amplified`) from `state["board"]["tiles"]`,
mirroring web `board.ts`. Dedup like the web client: gate on `moveIndex`
(`isNewMove = state["moveIndex"] > _last_move_index`) + a per-move `Dictionary` keyed
`"<status>-<r>-<c>"` (purge keyed per-column) so re-renders/resizes emit nothing.

```
Main (Control)                       ← ShakeRoot target (Control.position)
├── BoardView (Control)              ← existing; static grid of Panel cells (no positional slide in web)
│   ├── Cell_r_c (Panel + StyleBoxFlat)
│   │   ├── ValueLabel (Label)       ← glow ShaderMaterial (per-value); flash via StyleBoxFlat.bg_color tween
│   │   ├── EffectOverlay (TextureRect) ← assets/tile-effects/*; black_hole gets twist material
│   │   └── AmplifyBg (TextureRect)  ← z below ValueLabel; + MultiplierLabel
│   └── VfxLayer (Node2D)            ← pooled GPUParticles2D one-shots (coords = tile centers)
├── HudLayer (CanvasLayer)           ← SHAKE-IMMUNE: score/timer/combo, shard counter + ShardTarget(Marker2D), skulls
│   └── FloatingTextRoot             ← pooled Label floats; doober flight ends at ShardTarget
├── OverlayLayer (CanvasLayer, layer=100)
│   ├── GlitchRect (ColorRect, full-rect, MOUSE_FILTER_IGNORE) ← glitch .gdshader (hint_screen_texture)
│   └── CountdownLayer / MessageBanner (Label)
```

**Autoloads (in `scenes/`):**
- **`Vfx`** — `createEffect(name, world_pos)` dispatcher. Holds `const EMITTERS` table (counts,
  lifetimes-in-seconds, tint, blend, frame) mirroring `effects.json`. Pools `GPUParticles2D`
  one-shots, frees on `finished`.
- **`VfxMaterials`** — `get_glow_material(color, distance, strength, quality)` string-keyed cache;
  returns a shared `ShaderMaterial` (Godot resources are ref-shared = Pixi's `FilterCache`).
  **Only cache static materials** — the animated black-hole twist is per-instance.
- **`Anim`** — the central animation helper (resolved §2.7). All ex-RAF loops (countdown, banner,
  tooltip, selection pulse) route through here as time-based `create_tween()` chains. Also the home
  for shared helpers (`float_text`, `pulse`, `flash`).
- **`Quality`** — `enum Level { LOW, MEDIUM, HIGH }`; derives `glow_enabled`/`glow_quality`
  (LOW→false/0, MEDIUM→true/0.1, HIGH→true/0.3), `twist_enabled` (HIGH only), `quality_changed`
  signal, `ConfigFile` (`user://settings.cfg`), default LOW on touch else HIGH. **Note:** glow is
  the only per-tier knob in the source; gating particle amounts by tier is a net-new choice.

**Pooling:** floating text, doobers, and burst particles are numerous (one doober + one float
*per merged tile per swipe*) — pool the scenes rather than instance+free per event.

---

## 5. Per-system Godot recipes

### 5.1 Merge feedback trio (highest juice-per-effort — do first)

Three things fire together on `status=='merged'`: particle burst + bg-color flash + accumulated shake.

**White flash** (per merged cell):
```gdscript
func _flash(cell) -> void:
    var sb : StyleBoxFlat = cell['sb']
    var target_bg : Color = Style.tile_style(cell['value'])['bg']
    sb.bg_color = Color.WHITE
    if cell.has('flash_tw') and cell['flash_tw'] and cell['flash_tw'].is_running():
        cell['flash_tw'].kill()
    var tw := create_tween()
    cell['flash_tw'] = tw
    tw.tween_property(sb, 'bg_color', target_bg, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
```

**Screenshake** (once/move, value-scaled, fresh random/frame — not a single tween):
```gdscript
var _shake_t := 0.0
var _shake_dur := 0.0
var _shake_intensity := 0.0
var _base_pos : Vector2

func _ready() -> void:
    _base_pos = position   # capture root Control rest pos ONCE

func shake(intensity: float, duration_ms: float) -> void:
    position = _base_pos            # cancel-in-flight (mirrors fx.ts reset to 0,0)
    _shake_intensity = intensity
    _shake_dur = duration_ms / 1000.0
    _shake_t = 0.0

func _process(delta: float) -> void:
    if _shake_dur <= 0.0:
        return
    _shake_t += delta
    var x := clampf(_shake_t / _shake_dur, 0.0, 1.0)
    var eased := 1.0 - pow(1.0 - x, 3.0)         # cubicOut (ease.ts:41)
    var amp := _shake_intensity * (1.0 - eased)  # intensity*(1 - cubicOut(t))
    position = _base_pos + Vector2((randf()-0.5)*2.0*amp, (randf()-0.5)*2.0*amp)
    if x >= 1.0:
        position = _base_pos
        _shake_dur = 0.0

# trigger after the render loop:
if total_merge_value > 0:
    shake(minf(5.0 + (float(total_merge_value)/32.0)*0.5, 20.0), 200.0)
```
> The port is 100% Control-based, so `Camera2D.offset` is a no-op for the visible board — shake
> the root `Control.position`. If you migrate to world-space later, switch to `Camera2D.offset`
> and keep HUD/floating-text on a `CanvasLayer` so they stay shake-immune.

**Particle burst:** `Vfx.createEffect("merge", cell_center)` (see 5.2).
`cell_center = panel.position + Vector2(_tile/2, _tile/2)`; `_tile = BOARD_WIDTH(280)/board_size`
(70 at 4×4 — **don't hardcode 70**; scale glow/font by `tile_px/70`).

### 5.2 revolt-fx particles → GPUParticles2D

**One reusable "pop" preset** covers 7 point-burst emitters (new-tile, deck-ready, all `*-spawn`).
Swap texture (`res://assets/fx/frames/<frame>.png`) + color per effect:

```gdscript
# GPUParticles2D node
amount = 5
one_shot = true
explosiveness = 1.0      # burst = total count, not per-second
lifetime = 0.5           # JSON durationMax is already seconds
local_coords = false
# ParticleProcessMaterial
emission_shape = EMISSION_SHAPE_POINT
initial_velocity_min = 0.0
initial_velocity_max = 0.0
gravity = Vector3.ZERO
scale_min = 0.1
scale_max = 3.0          # scale_curve is a 0..1 multiplier of scale_max;
scale_curve = <Curve 0.03 -> 1.0>   # to reach scaleEnd≈3 you MUST set scale_max=3
color = Color(0.706, 0.0, 1.0)      # 0xB400FF
alpha_curve = <Curve 0.85 -> 0.0>   # 0.7..1 -> 0 fade (via color_ramp alpha)
```
- **Additive blend is a SEPARATE material slot:** set `CanvasItemMaterial.blend_mode =
  BLEND_MODE_ADD` on the **node's** `material` (CanvasItem.material). Per-particle color/alpha
  comes from the **ParticleProcessMaterial** `color_ramp`. Two different slots on one node.
- **NORMAL-blend exceptions:** `freeze-run`, `stone-removal` → leave `CanvasItemMaterial` default.
- **Bursts:** circle emitters (delete/bomb/consume) → `emission_shape = EMISSION_SHAPE_RING`/disc,
  radius 70, outward velocity 1–10 px/s, `scale_max = 2`.
- **Gravity removal bursts** (freeze/amplify/lock/stone removal): `gravity = Vector3(0, 0.35*scale, 0)`,
  velocity 1–10, amount 10–30. Stone adds `angular_velocity_min/max` (rotSpeed 0–0.0349 rad) +
  NORMAL blend + native color (`useTint=false`).

**Streak particles** (merge / purge-column / all `*-run`) — `scaleX 0.5→2`, `scaleY 0.1→0.2`
independently. **No `ParticleProcessMaterial` analogue** (uniform scale only). Needs a custom
particle `.gdshader` that stretches along velocity:
```glsl
// streak_particle.gdshader (high-effort, defer)
shader_type particles;
void process() {
    // anisotropic stretch: TRANSFORM scaled X by lerp(0.5,2,age), Y by lerp(0.1,0.2,age)
    // align long axis to VELOCITY; emit radially from box core
}
```
Alternative: `CPUParticles2D` with manual per-particle transform. The radial **merge** burst reads
fine on its own — **defer the streak shader** (single highest-effort particle item).

**`*-run` continuous emitters** (black-hole/freeze/amplify): `one_shot=false`, `emitting` toggled
by the tile-effect lifecycle, parented under the tile node so it follows.

### 5.3 Glow (per-object) — `.gdshader` (resolved §2.3)

Godot 4.6 has **no per-node Pixi-`GlowFilter` equivalent**. Per-`Label`/`TextureRect` outline-glow shader:
```glsl
// outline_glow.gdshader (canvas_item)
shader_type canvas_item;
uniform vec4 glow_color : source_color = vec4(0.706, 0.0, 1.0, 1.0);
uniform float glow_distance = 8.0;   // px, from TileValueStyles (8/12/15)
uniform float glow_strength = 1.0;   // outerStrength (1 or 2)
uniform float quality = 0.3;         // 0.1 MEDIUM / 0.3 HIGH -> tap count

void fragment() {
    vec4 src = texture(TEXTURE, UV);
    vec2 px = TEXTURE_PIXEL_SIZE * glow_distance;
    float taps = mix(4.0, 12.0, quality);
    float g = 0.0;
    for (float i = 0.0; i < 12.0; i++) {
        if (i >= taps) break;
        float a = (i / taps) * 6.28318;
        g += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px).a;
    }
    g = clamp(g / taps * glow_strength, 0.0, 1.0);
    vec3 col = mix(glow_color.rgb * g, src.rgb, src.a);
    COLOR = vec4(col, max(src.a, g));
}
```
- Value→glow table mirrors `TileValueStyles`: 8–64 white d8 s1, 128 white d12 s1, 256+ purple
  `0xb400ff` d15 s2; `quality` from `Quality.glow_quality`.
- **Cache & share** via `VfxMaterials.get_glow_material(...)`; don't mutate a shared material's
  params — make a new key. `0xb400ff` must be sRGB — `Color('b400ff')`; watch linear/sRGB.

### 5.4 Black-hole twist shader (HIGH only)

```glsl
// twist.gdshader (canvas_item)
shader_type canvas_item;
uniform float angle = 0.0;
uniform float radius = 1.0;   // normalized (radius 70 == tileSize)
void fragment() {
    vec2 c = UV - vec2(0.5);
    float d = length(c);
    float t = smoothstep(radius, 0.0, d);   // twist more toward center
    float a = angle * t;
    float s = sin(a), co = cos(a);
    vec2 uv = vec2(c.x*co - c.y*s, c.x*s + c.y*co) + vec2(0.5);
    COLOR = texture(TEXTURE, uv);
}
```
- **Drive `angle` per-second, not per-frame.** Web is `sin(time*0.02)*1` with `time +=
  ticker.deltaTime` (≈frames). Per-second: `mat.set_shader_parameter("angle", sin(time_sec*1.2)*1.0)`
  (≈ `0.02*60`). Naive seconds = ~60× too slow.
- **Per-instance material** (animated); only one black hole exists at a time. HIGH-only.

### 5.5 Full-screen glitch shader (blocked on engine task §2.2)

```glsl
// glitch.gdshader (canvas_item) on a top-CanvasLayer ColorRect (full-rect, mouse IGNORE)
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float u_slices = 10.0;
uniform float u_offset_px = 5.0;     // read live: 5 init, then 15..25 ramp/move
uniform float u_direction_deg = 0.0;
uniform float u_seed = 0.0;          // reseeded per move by engine
uniform float u_active = 0.0;        // optional ~120ms pop-in (ADDITIVE polish, not in source)
uniform vec2 u_screen_size = vec2(360.0, 640.0);
float rnd(float n){ return fract(sin(n*12.9898 + u_seed)*43758.5453); }
void fragment() {
    vec2 uv = SCREEN_UV;
    float ang = radians(u_direction_deg);
    vec2 dir = vec2(cos(ang), sin(ang));
    float band = floor(uv.y * u_slices);
    float shift = (rnd(band)*2.0 - 1.0) * (u_offset_px / u_screen_size.x) * u_active;
    vec2 disp = dir * shift;
    float ca = (u_offset_px * 0.4 / u_screen_size.x) * u_active;   // chromatic split
    vec4 c;
    c.r = texture(screen, uv + disp + vec2(ca,0.0)).r;
    c.g = texture(screen, uv + disp).g;
    c.b = texture(screen, uv + disp - vec2(ca,0.0)).b;
    c.a = 1.0;
    COLOR = c;
}
```
- `hint_screen_texture` auto-creates the back-buffer for a single full-screen `ColorRect` —
  **drop any `BackBufferCopy`** (only needed for multiple stacked screen-reading materials). Read
  `SCREEN_UV`, not `UV`. Must be the topmost draw. **Push `u_screen_size` on resize.**
- Read `filterConfig` live each frame from `state['globalEffects']` (engine reseeds `seed` and
  ramps `offset = 15 + rand*10` per move). Move-quantized — no ms fade in source; any `u_active`
  fade is additive polish, flag it.
- **Blocked:** `engine.gd:293 _process_global_effects` is a stub; complete it first (§2.2).

### 5.6 Doober + floating text (procedural, no assets)

**Doober** — the arc is an emergent artifact of x cubicInOut and y cubicOut over the same 600ms,
**not** a bezier/`Path2D`:
```gdscript
# Doober: Node2D root + Polygon2D diamond [(0,-8),(8,0),(0,8),(-8,0)] cyan + Line2D outline white w2
func fly(start: Vector2, target: Vector2) -> void:
    position = start
    modulate.a = 0.0
    var tw := create_tween().set_parallel(true)   # MUST be parallel or arc flattens to an L
    tw.tween_property(self, "modulate:a", 1.0, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(self, "position:x", target.x, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    tw.tween_property(self, "position:y", target.y, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var pulse := create_tween()
    pulse.tween_property($Icon, "scale", Vector2(1.3,1.3), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    pulse.tween_property($Icon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    var pop := create_tween().set_parallel(true)
    pop.set_delay(0.6)
    pop.tween_property($Icon, "scale", Vector2(2,2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    pop.tween_property(self, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    pop.chain().tween_callback(_on_arrived)   # unlock+apply pending shard, then queue_free
```
- **Shard-counter lock gate** is gameplay-felt: lock on spawn, apply pending value on `_on_arrived`.
  Keep in the **presentation layer** (`pending`+`locked` vars), never in `engine/`.

**Floating text:**
```gdscript
func float_text(pos: Vector2, text: String, color: Color, font_size: int, duration: float, distance: float) -> void:
    var l := Label.new()
    l.text = text
    var ls := LabelSettings.new()
    ls.font_size = font_size
    ls.font_color = color
    ls.outline_size = 4              # Pixi stroke width 4
    ls.outline_color = Color.BLACK
    l.label_settings = ls
    l.position = pos
    var tw := create_tween().set_parallel(true)
    tw.tween_property(l, "position:y", pos.y - distance, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tw.tween_property(l, "modulate:a", 0.0, duration/2.0).set_delay(duration/2.0).set_trans(Tween.TRANS_LINEAR)
    tw.chain().tween_callback(l.queue_free)
```
- Colors per call site: score green `0x00ff00` / high-combo yellow `0xffff00`; penalty red
  `0xff0000`; card variants `0xff4444` (bomb) / `0xff6600` (destroy) / `0x00ff00` (double single) /
  `0xffff44` (double row) / `0xff8844` (double adjacent). `direction` is **unused** — always rise.
- Put on the **HUD CanvasLayer** (shake-immune).

### 5.7 Card juice

`Node2D.skew` **exists** in Godot 4.6 (single shear angle, radians) — make the card a `Node2D` and
set `node.skew` directly for the wiggle. Independent `skew.x`/`skew.y` needs a custom `Transform2D`.
**Control nodes lack skew** — build the card as a `Node2D` for the wiggle. Flip's `cos(t*PI)` needs
`tween_method`.

### 5.8 Countdown + banner (route through `Anim`, resolved §2.7)

```gdscript
# CountdownLayer (CanvasLayer) > Overlay (ColorRect black) + NumberLabel (Grammara 120) + SubLabel
func run_countdown() -> void:
    overlay.modulate.a = 0.0
    create_tween().tween_property(overlay, "modulate:a", 0.7, 0.4)  # was RAF alpha+=0.05/frame
    for n in [3, 2, 1]:
        number.text = str(n)
        number.scale = Vector2(1.5, 1.5)
        var t := create_tween()
        t.tween_property(number, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        await t.finished   # ~1s per count
    number.text = "GO!"
    sub.visible = false
    var go := create_tween().set_parallel(true)
    go.set_delay(0.5)
    go.tween_property(number, "scale", Vector2(3,3), 0.4)
    go.tween_property(self, "modulate:a", 0.0, 0.4)   # grow + fade out
    await go.finished
    queue_free()
    Hud.show_message("Let's Play!", 1.0, 48)   # banner: fade-in -> tween_interval -> fade-out
```
Convert the per-frame RAF increments to **time-based** tweens (don't copy `alpha += 0.05/frame`).

---

## 6. revolt-fx migration strategy

**Recommendation: reimplement, partial.** Hand-port only the **~16 live emitters** into a
`const EMITTERS` table + presets — not a JSON-parsing runtime (half the bundle is dead; you'd be
re-porting a particle engine; CPU particles are slower). The frame PNGs are **already individual
files** in `assets/fx/frames/` — **no spritesheet slicing needed**; presets reference them directly.

- **Wave 1 (low, ~80%):** the "pop" preset for 7 point-bursts (new-tile, deck-ready, all `*-spawn`)
  + 3 disc bursts (delete, bomb, consume) + gravity-removal bursts. All stock `ParticleProcessMaterial`.
- **Wave 2 (high):** the streak `.gdshader` for merge/purge-column/`*-run`. The radial merge burst
  already reads well, so defer.

**Skip entirely:** `decay-*`, `amplify`-consume (don't exist), `splosion`/`merge-horizontal`/the
merge SEQUENCE (defined, never invoked), unused frames, `displacement.png` (red herring — twist,
not displacement), `*-zoomed.png` card art.

---

## 7. Prioritized roadmap (juice-per-effort, highest first)

Every item is **presentation-only** — reacts to `MbMatch` state/signals, never writes engine state.

- [x] **P0a · Trigger architecture** *(med)* — DONE (2026-06-04). `board_view.render` reads per-tile
  `status` + tracks `state["moveIndex"]`; `moveIndex` gate + per-move `shown` dedup dict; `Vfx`
  autoload (`scenes/vfx.gd`, registered in `project.godot`) + board-local `_vfx_layer` (Node2D).
  Unblocks every particle/flash/shake item. *(status/moveIndex confirmed present — §2.1.)*
- [ ] **P0b · Build the HUD** *(med)* — `HudLayer` CanvasLayer: score/timer/combo labels, shard
  counter + `ShardTarget` `Marker2D`, skull displays. Prerequisite for doober target, floating text,
  combo pop, HUD glow. *(resolved §2.5.)*
- [ ] **P0c · `Anim` helper autoload** *(low)* — central home for tween helpers + the ex-RAF loops
  (countdown/banner/tooltip/selection pulse). *(resolved §2.7.)*
- [x] **P1 · Merge feedback trio** *(low)* — DONE + verified live (2026-06-04). Merge particle burst +
  `StyleBoxFlat.bg_color` white flash (0.75s cubicOut, killed on the next direct bg set) + value-scaled
  board-`Control.position` shake (`min(5 + value/32*0.5, 20)`, 200ms, cubicOut decay, fresh `randf()`
  jitter in `_process`). HUD stays still (it's in the parent). Highest juice-per-effort.
- [~] **P2 · Particle Wave 1** *(low–med)* — PARTIAL. `Vfx.create_effect` dispatcher + `EMITTERS` table
  shipped using **CPUParticles2D** (not GPU — 2D-native `spread=180` radial is reliable from pure
  GDScript; GPU port deferred). Presets: new-tile, merge, delete, bomb-explode, purge-column, amplify,
  deck-ready; ADD blend via `CanvasItemMaterial`. The full board status diff (bombed/destroyed/purged/
  amplified/new) dispatches, but only **merge** + **new-tile** are visually verified — bomb/destroy/
  purge/amplify fire but are unseen; tile-effect `*-spawn/run/removal` + gravity/NORMAL-blend variants
  still TODO. Values in the table are first-pass, eyeball-tune later.
- [ ] **P3 · Countdown intro + "Let's Play!" banner** *(low)* — first thing the player sees; via `Anim`.
- [ ] **P4 · Floating score text + shard doober** *(low–med)* — pure procedural, no imported assets;
  doober keeps the presentation-side lock/pending gate.
- [ ] **P5 · Combo pop + HUD glow** *(low)* — elastic→cubic combo punch (`pivot_offset=size/2`);
  outline-glow material on HUD value label, gated by `Quality`.
- [ ] **P6 · Tile value-text glow + tile-effect overlays** *(med)* — per-value glow table mirroring
  `TileValueStyles`; `assets/tile-effects/*` overlays into the `TextureRect`; amplify bg + gold mult.
- [ ] **P7 · Quality autoload** *(low)* — LOW/MEDIUM/HIGH, `ConfigFile`, gates glow (+ optional
  particle amounts, flagged net-new).
- [ ] **P8 · black-hole destroy fly + consume + twist** *(med)* — temp `Label` flown to target
  (400ms cubicIn, scale→0) + consume burst + red `-value` float; twist `.gdshader` HIGH-only with
  the `sin(time_sec*1.2)` frame→seconds fix.
- [ ] **P9 · Card juice** *(low–med)* — disabled `self_modulate`, card glow material, flip
  (`tween_method` `cos(t*PI)`), wiggle (`Node2D.skew`), description panel. Confirm flip is needed.
- [ ] **P10a · Complete `_process_global_effects`** *(med, engine-parity)* — port `globalEffects.ts`
  (tick `movesRemaining`, reseed, ramp `offset`, drop at 0); **re-verify against a golden**. *(§2.2.)*
- [ ] **P10b · Full-screen glitch** *(med)* — `ColorRect` + glitch `.gdshader` (`hint_screen_texture`,
  no `BackBufferCopy`). Depends on P10a or it won't tick.
- [ ] **P11 · Streak particle shader (Wave 2)** *(high — defer)* — anisotropic `scaleX≠scaleY` for
  merge/purge/`*-run`. Single highest-effort item; radial merge already reads well.
- [ ] **Optional / net-new** *(skip unless desired)* — totem spawn/idle/trigger juice (source has
  none), score/shard **count-up** (source replaces instantly), positional tile-slide tweens (web
  never slides — pure repaint+particles). Allowed as enhancements; flag as divergence.
- [ ] **Do NOT port** — decay/amplify-consume emitters, splosion/merge-sequence, unused frames,
  `displacement.png`, `*-zoomed.png`, per-card "spell" beam/spiral/storm shaders (**they don't exist**
  — cards only do score floats + status-driven bursts).

---

## 8. Remaining risks / fidelity gaps

- **No native Pixi `GlowFilter`.** Resolved to per-node outline `.gdshader` (§2.3) — preserves
  per-value distance/strength tuning; no global bloom.
- **Streak particles** (`scaleX≠scaleY`) have no `ParticleProcessMaterial` path — needs the custom
  particle shader (P11).
- **`back`/`elastic` curve shapes** differ from web (web `backOut` overshoot 2; elastic constants
  13/10/π2). Resolved: **close enough** (§2.6) — use `TRANS_BACK`/`TRANS_ELASTIC`. `cubic`/`bounce`
  are identical to built-ins.
- **revolt-fx silhouettes** depend on the frame PNGs (present in `assets/fx/frames/`) — fidelity is
  good; the only gap is the streak stretch (P11).
- **Glitch depends on an engine task** (P10a) — until `_process_global_effects` ticks/reseeds, the
  glitch state never animates. Keep it a golden-verified parity change, separate from the VFX work.
