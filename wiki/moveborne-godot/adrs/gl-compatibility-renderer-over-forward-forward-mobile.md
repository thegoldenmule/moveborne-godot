# ADR-10: GL Compatibility renderer over Forward+/Forward Mobile

**Status:** accepted

## Metadata
- **Date:** 2026-06-04
- **Scope:** Client / Rendering
- **Deciders:** Benjamin Jordan

## Context
The project initially targeted the Forward+ / Forward Mobile renderer (the README still references Forward Mobile, portrait). During development the game showed janky, unstable FPS on macOS. Moveborne is a 2D portrait puzzle that does not need Forward+ lighting features; the priority is smooth, predictable frame pacing on the dev machine and mobile targets. (Commit 02eed84.)

## Decision
Switch the renderer to GL Compatibility (project features now declare 4.6 and GL Compatibility). This trades the advanced Forward+ feature set, which the 2D puzzle does not use, for stable frame pacing on macOS during development and broad device support. Paired with deterministic VFX-node cleanup after an earlier leak of roughly 22 thousand nodes had tanked FPS to about 10.

## Consequences
POSITIVE: Smooth, predictable FPS on macOS dev and wide low-end device compatibility; faster shader compiles; well-suited to a 2D portrait game.

NEGATIVE / COST: No access to Forward+ only features (advanced 3D lighting, SDFGI, some post effects); shaders must stay within GL Compatibility limits. The README still mentions Forward Mobile and should be reconciled. Mobile shader compile still needs verification.

## Relations
_None._
