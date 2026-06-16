# ADR-23: One committed story catalog feeds validator grading, Remote Config, and the baked client fallback

**Status:** superseded

## Metadata
- **Date:** 2026-06-12
- **Scope:** content pipeline (validator, Remote Config, game client)
- **Deciders:** Benjamin Jordan

## Context
Story levels are pure data (worlds, levels mapped onto existing scenario ids, three goals each, per-star rewards) consumed by three surfaces: the validator that grades, the client that renders the map and HUD, and live tuning. Drift between any two surfaces shows up as players losing stars the UI promised. The validator Docker build context is validator/, so the deployable service must carry its own copy.

## Decision
validator/content/story_catalog.json is canonical. It ships inside the validator image, is published verbatim to the Remote Config app-config (version v1, under the story_catalog key so later features can share the document), and is byte-copied to game/story/story_catalog.json as the offline/dev fallback.

The client adopts the remote catalog only when it is structurally valid AND its catalog_version is at least the baked copy's — a stale or malformed remote payload can never downgrade a shipped client.

Parity is test-enforced: a bun test and the verify_story_catalog headless verifier byte-compare the two committed copies, and tools/story-appconfig.ts emit|verify publishes and canonically compares the live app-config (the gateway echoes config with alphabetized keys, so comparison must be key-order-insensitive).

## Consequences
One edit point for all tuning; catalog_version detects cross-surface drift.

Remote Config has no write API, so publishing is a console step wrapped by the emit/verify helper. Threshold changes that affect grading still require a validator redeploy to keep grading and display in lockstep — the verify tooling flags deployed-surface drift but cannot prevent it (procedural).

Levels may only reference existing MbScenarios ids (0-17); genuinely new mechanics are TS-first scenario work with regenerated golden vectors.

## Relations
- **Superseded by** → [Validator pulls the story catalog from Remote Config at runtime; per-match version pinning + init handshake (supersedes ADR-23)](decision-record:mqgt1goe-00mt-1b16ck)
