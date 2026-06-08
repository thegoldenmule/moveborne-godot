# ADR-9: Rebuild VFX natively in Godot instead of porting the PixiJS pipeline

**Status:** accepted

## Metadata
- **Date:** 2026-06-03
- **Scope:** Client / Presentation & VFX
- **Deciders:** Benjamin Jordan

## Context
The original Moveborne client renders with PixiJS and a bespoke `render/`, `fx/`, and `animation/` stack (sprites, filters, tweens). None of that is portable to Godot. The hard wall ([[ADR-0003]]) means presentation is downstream of the engine and free to change, so there is no parity reason to imitate the PixiJS pipeline — only a visual-fidelity reason to match the *look*.

## Decision
Rebuild the VFX natively with Godot primitives instead of porting the PixiJS pipeline: CPUParticles2D and GPUParticles2D for bursts, ShaderMaterial overlays and full-screen passes for glitch, glow, and black-hole twist, and AnimationPlayer or tweens for tile pop, spawn, slide, and shake. Drive every effect off published state plus moveIndex (never engine internals). The Moveborne-to-Godot effect mapping and phased roadmap live in the VFX mapping reference doc.

## Consequences
POSITIVE: Effects use the renderer's strengths (GPU particles, shaders) and can be tuned or rebuilt without any risk to determinism. The mapping doc gives a clear, incremental roadmap rather than a one-to-one PixiJS reimplementation.

NEGATIVE / COST: Visual parity with the original is approximate and hand-tuned, not guaranteed. VFX is a large, open-ended surface (tile-effect emitters, glow, glitch, doobers, floating text) that lands incrementally, and some effects depend on engine paths (the global-effects glitch tick) being completed first.

## Relations
_None._
