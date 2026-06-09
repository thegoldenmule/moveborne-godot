# Moveborne — Art Style Guide & Concept Context

> Extracted from `art/MoveBorne.psd` (5100×3300, 12 top-level concept groups).
> Rendered boards live in `art/extracted/`; individual moodboard references in
> `art/extracted/reference/`. This document is the LLM-readable distillation of that file —
> treat it as the source of truth for art direction language; treat the PNGs as visual evidence.

## 1. The concept in one paragraph

Moveborne's target art direction is **occult arcade**: a 2048-style merge board re-skinned as a
tarot ritual. Neon **violet (#A100FF family) line-work on near-black**, screen-print grain, mystic
iconography (tarot arcana, skeletons, eyes of providence, moons, sigils) collided with **Y2K
"acid graphics"** techno-poster design (wireframe grids, barcodes, registration marks, chrome-rave
typography). Powerup cards are literally **tarot cards**. The current shipped look (warm wood,
parchment, orange) is the *before*; this PSD is the *after*. (Legacy renders are deliberately
not kept in `extracted/` — the legacy style appears only inside the PSD itself.)

**Mood keywords:** occult, tarot, neon-violet, blacklight poster, screen-print / risograph,
acid graphics, Y2K rave flyer, memento mori, wireframe, monochrome-plus-one-accent.

## 2. Color palette

One accent color over black. Everything reads as black / violet / white.

| Role | Hex | Notes |
|---|---|---|
| Background black | `#000000`–`#141414` | Never flat: always carries grunge/screen-print texture (see §7) |
| Primary accent (violet) | `#A100FF` | The authored fill color of all accent type in the PSD |
| Accent, glow-boosted | `#BC00FB`–`#C600FF` | What the accent reads as after glow/screen effects |
| Deep violet shades | `#280038`, `#43005D`, `#690083`, `#8C00C4` | Dim outlines, empty cells, secondary line-work |
| White | `#FFFFFF` | Highest-emphasis tier: top tiles, key numerals, alt line-work |
| Legacy palette (current build) | warm wood browns, parchment `#D7C2AF`, orange `#FFA200` | The *old* style being replaced; kept in PSD only for contrast |

Rules of thumb:
- **Hierarchy is value, not hue**: dim violet outline → solid violet fill → white fill.
- White and violet are never mixed half-and-half on one element; an element *is* violet or *is* white.
- No gradients in the line-art itself; glow halos around violet strokes are fine.

## 3. Typography

Authored fonts found in the type layers, with the roles the mockups give them:

| Font | Role in mockups |
|---|---|
| **Grammara** (Normal) | Workhorse UI font: HUD labels (TIME / SCORE / SHARDS), tile numerals, COMBO meter, button text. Squared techno display face, all-caps. |
| **OldEnglishFive** (blackletter) | Brand/flavor alternative: the `Mockup with different font` + `Type Effects` boards set the MOVEBORNE logo, "Deck", "Shards" labels in blackletter while keeping Grammara for numbers. This pairing (blackletter brand + techno UI) is the apparent final direction. |
| **WAXEN** | Logo treatment on the tarot-sheet reference board (vertical MOVEBORNE). |
| **SFHallucination** | Logo treatment on the Art Style board — psychedelic display face. |
| **LadyStarlight** | Card titles on tarot powerup cards (BOOST, Lightning, Vortex). |

Candidate list explored on the Typography Ideas board (`extracted/05`): Bagrile, Serif Gothic Std
Black, WAXEN, Chomsky, Breitkopf Fraktur, DieNasty, Firlest, LadyStarlight, RunyTunes Revisited,
OldEnglishFive, Nougat ExtraBlack, Tarot Pamela Colman Smith, SFHallucination, Grammara.
The shortlist that actually gets used downstream: **Grammara + a blackletter (OldEnglishFive/Chomsky
family) + LadyStarlight for card titles**.

Typographic habits: all-caps for HUD; generous letter-spacing; the logo runs **vertically** up the
left edge of the screen; numerals may be stacked two-per-line at large sizes ("20 / 48" for 2048).

## 4. Screen / UI anatomy (from the Mockup boards)

The mockup (`extracted/03-mockup-ui.png`, `04-type-effects.png`) is a portrait screen framed by a thin violet rule
(rounded-corner rectangle inset from the screen edge), like a printed poster border:

- **Top bar**: three-column scoreboard — TIME / SCORE / SHARDS — violet labels, white values,
  separated by violet rules.
- **Combo meter**: "1X COMBO" below the scoreboard; ghosted repeat lines under it suggest the
  multiplier ticking up (stacked echo effect).
- **Board**: 4×4 grid of square cells, thin violet strokes on black. No card-stock tiles — cells are
  wireframe; the *value styling* carries hierarchy (see §5).
- **Hand / cards**: bottom-left fan of 2–3 tarot cards (the active one popped up and labeled, e.g.
  SWAP); inactive cards rendered as dim violet line-art backs.
- **Deck**: bottom-right tarot card-back with an all-seeing-eye sigil, "DECK" label + count (15).
- **Shards meter**: a row of 10 small tick rectangles (filled = earned) labeled SHARDS.
- **Logo**: MOVEBORNE running vertically along the far-left edge, full screen height.

## 5. Tile value styling (from the Type Effects board)

Tiles escalate dim → violet → white, with pattern fills as flourishes:

- **Low values**: dim deep-violet outline numerals on black cells (barely-there, ghost tier).
- **Mid values**: solid violet cell fill with black numeral, or violet numeral on black.
- **High values**: white cell fill with black numeral / white numerals — white = peak emphasis.
- **Milestones**: pattern-filled cells (concentric rings, halftone dots, crosshatch — three swatches
  are provided on the board) instead of flat fills.
- **2048**: numeral stacked on two lines ("20" over "48") inside a violet cell.

## 6. Cards (the tarot system)

Two visual registers, both explored on the Art Style + Card Ideas boards:

1. **Illustrated tarot** (`extracted/07`): full tarot pastiche — skeleton figures (dancing,
   scythe-bearing, à la the *La Morte* / Death card), flames, moons, starfields, ornamental
   borders, Roman-numeral headers, name plate at the bottom (BOOST). Two colorways: violet-on-black
   and white-on-black.
2. **"Primitive cards"** (`extracted/09`): abstract acid-graphics tarot — card frames containing a
   single wireframe/op-art glyph (vortex tunnel, concentric rings, lightning bolt, dot matrix,
   warped grid, sphere, crescent) with the card name in a violet banner (VORTEX / BOOST /
   LIGHTNING). This register is cheaper to produce and matches the board's wireframe style.

Card anatomy in both: rounded-rect outer frame → inner art window → name banner near the bottom.
Card backs: centered occult sigil (eye in rays) in dim violet line-work.

## 7. Texture & finish

- A full-screen **dark grunge / screen-print texture** (`extracted/11`) multiplies over everything —
  dust, press streaks, paper scuffs. The black must never be clinically clean.
- Violet elements get a slight **glow/bloom** (hence #A100FF reading as ~#C600FF).
- Halftone, crosshatch and moiré patterns are the approved "shading" vocabulary — no soft airbrush
  shadows inside the line-art.
- Edge treatments: thin double rules, registration-mark corners, barcode strips are in-vocabulary
  (see the acid-poster references).

## 8. Motif library

Approved iconography (all present in the PSD): tarot major arcana (Sun, Lovers, Fool, Moon,
Magician, Empress, Hermit, High Priestess, Tower), skeletons / memento mori, all-seeing eyes with
radiating lashes, crescent moons and phases, stars/sparkles, sigils, ornamental card borders,
wireframe globes & tunnels, warped checkerboards, lightning bolts, barcodes, concentric circles,
op-art dot grids.

## 9. Gameplay concept text (transcribed from the Powerup List board)

**Primitive cards** (one-shot effects):

| Card | Effect |
|---|---|
| Divide | Divides a selected tile's value in half. |
| Shuffle | Shuffles all tiles on the board. |
| Lightning | Doubles all tile values in a selected column. |
| Radiate | Doubles all adjacent tiles to selected tile. |
| Clone | Duplicates a selected tile onto a selected empty space. |
| Swap | Swaps the position of two tiles. |
| Vortex | Rotates all tiles in a selected 2×2 quadrant. |
| Multiply | Doubles the value of a selected tile. |
| Teleport | Moves a selected tile to a selected empty space. |

**Totem cards** — cards that may have an immediate effect but also spawn a **Totem**: a
multi-turn effect shown as a small icon above the board with a turns-remaining counter.

| Card | Effect |
|---|---|
| Energy Catalyst | All spawned tiles are 4s. |
| Power Amplifier | All spawned tiles are 8s. |
| Chaos Engine | All spawned tiles are 16s. |
| Combo Saver | Prevents combo from breaking. |
| Chrono Anchor | Can rewind to snapshot. |
| Magnet Core | Tiles move towards center after spawn. |
| Momentum Idol | Adds +1 to combo multiplier increments. |
| Void Gate | Removes lowest tile instead of spawning on failed swipes. |
| Ghost Merge | First merge in swipe echoes to random empty cell (5 uses). |

(Card names seen in the art but not in this list — e.g. **Boost** — are art-side working names.)

## 10. Do / Don't for generated art & UI

**Do**: one accent color (violet) on textured black; wireframe line-art; tarot framing for anything
card-shaped; blackletter for brand moments, techno caps for data; halftone/op-art pattern fills;
white reserved for peak emphasis.

**Don't**: introduce extra hues; use the legacy wood/parchment style; soft gradients or drop
shadows inside illustrations; clean untextured backgrounds; mixed-case body-text-style UI labels;
rounded friendly "casual game" blobs.

## 11. Extracted asset index

| File | What it is |
|---|---|
| `extracted/03-mockup-ui.png` | Full screen mockup with blackletter brand font (apparent final direction) |
| `extracted/04-type-effects.png` | Tile value styling tiers + pattern fill swatches |
| `extracted/05-typography-ideas.png` | 14 logo font candidates |
| `extracted/06-reference.png` | Moveborne tarot sheet — 9 arcana cards, white & violet colorways |
| `extracted/07-art-style.png` | Card style candidates (illustrated skeleton tarot) + acid-glyph grid |
| `extracted/08-reference-2.png` | Moodboard: acid-graphics posters + minimal tarot decks |
| `extracted/09-card-ideas.png` | "Primitive cards" — abstract wireframe tarot card designs |
| `extracted/10-powerup-list.png` | Text spec of primitive + totem cards (transcribed in §9) |
| `extracted/11-screen-texture.png` | Full-screen grunge/screen-print overlay texture |
| `extracted/reference/mood-1-*.png` | Individual moodboard images: acid posters (layers 9–12), tarot decks (layers 6–8, 583) |
| `extracted/reference/mood-2-*.png` | Hidden refs: tarot deck collections, eye/La-Morte studies, music posters (Weeknd, Billie Eilish, Megan Thee Stallion) |

### Regenerating renders

Renders were produced with `psd-tools[composite]` (Python). Top-level groups are mostly *hidden*
in the PSD — set `layer.visible = True` before calling `layer.composite()`, or you get black output.
