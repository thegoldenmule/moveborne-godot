# ADRs

**Status:** active

## Overview
Two spines run through these decisions. The first is **determinism**: making the GDScript rules engine byte-for-byte identical to the canonical TypeScript engine, which is what lets the client play optimistically against the unchanged validator and drives the choices around state representation, mutation semantics, pure-logic structure, and golden-vector testing. The second is **LLM-driveability**: deliberately building the game so an agent can both play it and verify it, which motivates message-based input, a consolidated two-tier state, the play-and-observe verification loop, and treating tests as strategic rather than universal. The two reinforce each other — determinism is what makes agent-driven replay and bug-repro possible.

The remaining records cover backend scope, the presentation and rendering approach, and which source is authoritative when code and spec disagree. All are recorded as accepted.

## Contents
- **Accepted Decisions** — Decisions already made and shipped (Phases 0–3), recorded retroactively.
  - [Byte-for-byte determinism parity with the canonical TS engine](decision-record:mq1clkoc-0001-6lu4vz)
  - [Optimistic client updates with authoritative validator reconciliation](decision-record:mq1cllv4-0003-shzk9m)
  - [Hard wall between deterministic logic and presentation](decision-record:mq1cloi4-0005-d7fpa8)
  - [Defer Nakama; ship local-authoritative single-player first](decision-record:mq1clpji-0007-t9abfq)
  - [Game state as an untyped Dictionary mirror of SynchronizedGameState](decision-record:mq1clqiq-0009-klfz9b)
  - [Mirror JS mutation semantics via GDScript references + shallow duplicate](decision-record:mq1cls7s-000b-ol8ps9)
  - [Pure logic as static class_name utilities, not autoloads](decision-record:mq1cltbf-000d-5bg2ec)
  - [Golden-vector parity testing from the real TS dist via McpTestSuite](decision-record:mq1clufu-000f-uyq2mx)
  - [Rebuild VFX natively in Godot instead of porting the PixiJS pipeline](decision-record:mq1clvcg-000h-7f05vp)
  - [GL Compatibility renderer over Forward+/Forward Mobile](decision-record:mq1clyer-000j-p8ya0s)
  - [Code beats spec; rules from src/logic, scenarios/UI from src/game](decision-record:mq1clzbf-000l-22sw0l)
  - [Design the game to be driven and verified by an LLM](decision-record:mq1ebq40-0001-hgjnmt)
  - [Two-tier game state — local vs synchronized](decision-record:mq1ebry9-0003-sfhuso)
  - [Unify all player input as messages through a single interface](decision-record:mq1ebtkg-0005-vfahik)
  - [Fun-first — test the deterministic core, verify the game by playing it](decision-record:mq1ebvcb-0007-cmmi2x)
- **Ungrouped**
  - [Adopt Snapser as the online backend, replacing Nakama](decision-record:mq74gj5v-000c-9ta022)
  - [Authenticate BYOSnap requests by trusting gateway-stamped User-Id, not signatures](decision-record:mq74gkil-000e-cwpjw6)
