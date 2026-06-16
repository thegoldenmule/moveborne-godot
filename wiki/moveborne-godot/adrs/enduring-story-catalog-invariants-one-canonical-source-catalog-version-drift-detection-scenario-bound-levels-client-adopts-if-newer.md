# ADR-26: Enduring story-catalog invariants: one canonical source, catalog_version drift detection, scenario-bound levels, client adopts-if-newer

**Status:** accepted

## Metadata
- **Date:** 2026-06-16
- **Scope:** content pipeline (validator, Remote Config, game client)
- **Deciders:** Benjamin Jordan

## Context
ADR-23 is superseded by the companion record 'Validator pulls the story catalog from Remote Config at runtime; per-match version pinning + init handshake' (decision-record:mqgt1goe-00mt-1b16ck), which changes HOW the catalog is distributed to and consumed by the validator. Several of ADR-23's decisions are orthogonal to that distribution change and remain in force. This record carries those enduring invariants forward so they live in a current, accepted ADR rather than only inside the superseded one.

## Decision
One canonical source. validator/content/story_catalog.json is the single hand-edited source of the story catalog; every surface derives from it — validator grading, the Remote Config app-config (version v1, key story_catalog), and the client baked copy at res://story/story_catalog.json (now a generated, byte-verified artifact). The distribution + runtime-load mechanics are governed by the companion record.

catalog_version is the cross-surface drift detector. Every surface stamps or echoes catalog_version, and tooling compares it across the committed file, the live Remote Config app-config, and the deployed validator's loaded catalog so divergence is visible rather than silent.

Levels reference only existing MbScenarios ids (0–17). Genuinely new mechanics are TS-first scenario work with regenerated golden vectors; story content stays outside the determinism hash domain (hard-wall ADR).

Client adopt-if-newer. The game adopts the remote catalog only when it is structurally valid AND its catalog_version is at least the baked copy's, so a stale or malformed remote payload can never downgrade a shipped client (MbRemoteConfigClient.select_catalog).

## Consequences
One edit point for tuning, and drift across surfaces is detectable rather than silent (catalog_version + the verify/status tooling).

Story content is bounded by the existing scenario set (0–17) until new scenarios ship TS-first with regenerated goldens.

Distribution, the validator's runtime source, per-match version pinning, and the init-time version handshake are governed by the companion record (decision-record:mqgt1goe-00mt-1b16ck); this record is intentionally limited to the invariants that survived the supersession of ADR-23.

## Relations
_None._
