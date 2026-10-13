# Spec — Story catalog from Remote Config — single committed source, validator pulls at runtime, editor sync/publish helper

**Status:** sealed

## Overview
The story catalog is the validator's RUNTIME source: pulled from the Snapser Remote Config snap (s2s) at boot and on a TTL, NOT bundled in the validator image. validator/content/story_catalog.json is the single hand-edited source; the byte-identical game/story/story_catalog.json is generated from it; publishing to Remote Config is a manual console paste. Story matches pin the catalog_version they init with (graded against it for life), and client+validator agree on a version via an InitMatch handshake. Shipped 2026-06-16 (commits f2daeb0, b7ef5b1, 902b42a, 1edcea8; +catalog editor 8775264/ece1286).

## Design
_No design yet._

## Decisions
Refresh cadence: boot-load + short TTL re-fetch + an on-demand POST /api/story/catalog/refresh endpoint — all three, so live content reaches the validator without a redeploy. Validator catalog refresh cadence: (a) boot-load only — restart to pick up a new catalog (simplest, fewest moving parts); (b) boot-load + short TTL/periodic refetch; (c) on-demand refresh endpoint. RECOMMEND (a) boot-load only for v1 (a redeploy/restart already accompanies threshold changes per ADR-23), revisiting TTL later. Which do you want?

Startup/refresh failure: serve LAST-KNOWN-GOOD (a failed/invalid refresh keeps the in-memory cache, never downgrading to empty); cold boot retries with backoff until the first good load while non-story matches keep serving. Production startup when Remote Config is unreachable (no committed copy in the image): (a) fail-fast — refuse to grade STORY matches (return an error), non-story matches unaffected, with retry/backoff; (b) serve a last-known cached catalog. RECOMMEND (a) fail-fast with retries — grading on missing/guessed data is worse than a clear error. Acceptable?

Editor sync/publish UI lives in the existing story_map_editor dock (a Remote Config tab), since it checks/publishes that specific catalog. Where the sync/publish UI lives: (a) a 'Catalog ⇄ Remote Config' panel/tab inside the existing addons/story_map_editor dock; (b) a separate dedicated dock. RECOMMEND (a) — it's the existing story-authoring surface and already loads the catalog. Preference?

Sync check reuses the canonical TS comparator (the dock shells out to `bun tools/story-appconfig.ts verify`) rather than reimplementing the key-order-insensitive compare in GDScript. How the editor computes sync status: (a) reuse the canonical TS comparator by shelling out to `bun tools/story-appconfig.ts verify` (one source of truth for the key-order-insensitive compare) via OS.execute/a bridge; (b) reimplement anon-login + GET + canonical compare natively in GDScript. RECOMMEND (a) to avoid duplicating the comparator. Okay?

Single committed source: the client baked copy is GENERATED from the canonical file (tools/sync-catalog.ts) and byte-verified (verify_story_catalog.gd / sync:catalog:check), not hand-maintained. Single-file mechanics for the client baked copy: (a) generate game/story/story_catalog.json via tools/sync-catalog.ts + byte-verify (recommended); (b) symlink it to the canonical file (fragile across Godot import/git/Windows); (c) have Godot fetch at editor time. RECOMMEND (a). Agree?

## References
_None._

## Child pages
_None._
