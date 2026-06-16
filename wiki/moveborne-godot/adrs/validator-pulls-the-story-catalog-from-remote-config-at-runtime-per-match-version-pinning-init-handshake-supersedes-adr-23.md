# ADR-25: Validator pulls the story catalog from Remote Config at runtime; per-match version pinning + init handshake (supersedes ADR-23)

**Status:** accepted

## Metadata
- **Date:** 2026-06-16
- **Scope:** content pipeline (validator, Remote Config, game client)
- **Deciders:** Benjamin Jordan

## Context
ADR-23 made validator/content/story_catalog.json canonical and **bundled it into the validator image** (a compile-time JSON import), with game/story/story_catalog.json kept as a byte-identical twin and Remote Config published by a manual console paste. That couples the validator's grading data to a redeploy: any live tuning a designer publishes to Remote Config reaches the client but NOT the deployed validator until the image is rebuilt, and threshold changes that affect grading require a redeploy to stay in lockstep. We want (a) live content to reach the validator without a redeploy, (b) genuinely one hand-edited source on disk, and (c) grading that stays consistent for a match's entire duration even while content refreshes underneath it. The Snapser team confirmed Remote Config has NO app-config write API, so publishing remains a manual console step regardless.

## Decision
Remote Config (app-config version v1, key story_catalog) becomes the validator's RUNTIME source of truth. At boot the validator fetches the catalog over the existing s2s transport (internal SNAPEND_REMOTE_CONFIG_HTTP_URL + the Gateway internal header; api-key gateway fallback; committed-file fallback only when both are absent, i.e. local dev), runs validateCatalog, and caches it. The compile-time JSON import is removed and content/story_catalog.json is .dockerignored — the catalog is NO LONGER bundled in the validator image.

Refresh policy: boot-load + a short TTL re-fetch + an on-demand refresh endpoint. The validator serves LAST-KNOWN-GOOD — a refresh that fails or returns an invalid payload keeps the in-memory cache and is logged; it never downgrades to empty. Cold boot (no cache yet) retries with backoff until the first successful load, with non-story matches available meanwhile.

Per-match version pinning (no wipe): the validator keeps a REGISTRY of catalog versions rather than a single mutable cache. A story match pins the catalog_version it was initialized with and is graded against THAT version for its whole life. Versions are ref-counted (retain at init, release at completion/expiry); a version is evicted only when unreferenced AND not the current version. A TTL refresh or a new publish can never change an in-flight match's grading basis.

Initial-handshake version agreement: story InitMatch carries the client's catalog_version, and client + validator converge on one version before play. Equal → pin it. Client AHEAD → the validator force-refreshes from the same Remote Config source and re-checks. Client BEHIND (or still mismatched) → the init is rejected with the validator's current version so the client re-fetches Remote Config and retries. The InitMatch response returns the agreed/pinned version. Story matches only — Infinite/PvP carry no catalog.

Single committed source: validator/content/story_catalog.json remains the ONE hand-edited file — the publish seed and the dev/test fallback. game/story/story_catalog.json becomes a GENERATED, byte-verified artifact (tools/sync-catalog.ts; the verify_story_catalog.gd byte-compare is the guard). Publishing to Remote Config stays a manual console paste (no write API), assisted by emit/verify/status tooling and an editor sync panel that shows committed-vs-live drift + the live catalog_version.

```typescript
// Essence: a version registry + per-match pin + init handshake (validator side)
const versions = new Map<number, IndexedCatalog>();  // retained while referenced; `current` never evicted
const refs = new Map<number, number>();
let current = 0;

function adopt(c) { validateCatalog(c); versions.set(c.catalog_version, index(c)); current = c.catalog_version; }
function getLevelAt(v, id) { return versions.get(v)?.levelsById.get(id); }   // grading reads the PINNED version
function retain(v) { refs.set(v, (refs.get(v) ?? 0) + 1); }
function release(v) { const n = (refs.get(v) ?? 0) - 1; if (n > 0) refs.set(v, n);
                      else { refs.delete(v); if (v !== current) versions.delete(v); } }

async function pinVersion(clientVersion) {            // story InitMatch handshake
  let v = current;
  if (clientVersion === v) return v;                 // agree
  if (clientVersion > v) { await refreshCatalog(); v = current; if (clientVersion === v) return v; }
  throw new ServiceError(FAILED_PRECONDITION, "catalog_version_mismatch", { current: v });
}
// init: const v = await pinVersion(req.catalog_version); retain(v); stored.catalog_version = v; resp.catalog_version = v;
// grade: getLevelAt(match.catalog_version, level_id);  teardown: release(match.catalog_version);
```

Supersession: this record fully supersedes ADR-23 ('One committed story catalog feeds validator grading, Remote Config, and the baked client fallback'). The clauses it CHANGES — the catalog ships inside the validator image, and grading-threshold changes require a validator redeploy to stay in lockstep — are replaced here by the runtime Remote Config pull + per-match version pinning + init-time version handshake. ADR-23's enduring invariants (one canonical source; catalog_version drift detection; scenario-bound levels; client adopt-if-newer) are NOT discarded — they are carried forward unchanged in the companion record 'Enduring story-catalog invariants' (decision-record:mqgt8d42-00nq-wcx3vt).

## Consequences
Live tuning reaches the validator without a redeploy — a published catalog is picked up at boot, on the TTL, or via the on-demand endpoint. Grading is no longer pinned to a deploy; cross-surface lockstep becomes EVENTUAL rather than deploy-tied, made safe by per-match pinning + the init handshake and observable via catalog_version logging and the status tool.

New runtime dependency: with no embedded copy, the production validator needs the remote-config snap reachable at cold boot. Retry/backoff + last-known-good mitigate steady-state outages, but a cold boot during a Remote Config outage delays story grading (non-story matches unaffected).

Catalog accessors become version-scoped (getLevelAt(version, id)) and the load path becomes async (an awaited boot load) instead of a synchronous module const. The version registry holds more than one catalog only across a publish while older matches are still live, and drains back to one as those matches end.

Wire change: InitMatchRequest/InitMatchResponse gain catalog_version (regenerate godobuf bindings, the protobufjs descriptor, and swagger). The client must send its version on story init and handle a catalog_version_mismatch by refreshing Remote Config and retrying once.

Publishing remains a manual Snapser console paste (no app-config write API, confirmed with the Snapser team). The tooling can emit the payload, verify live-vs-committed, and report versions across surfaces, but cannot push.

The committed catalog is no longer in the image, but it stays in the repo as the publish seed + dev/test fallback; the client baked copy is generated from it and byte-verified, so 'one edited file' holds without losing Godot's need for an on-disk res:// copy.

## Relations
- **Supersedes** → [One committed story catalog feeds validator grading, Remote Config, and the baked client fallback](decision-record:mqbfd5mc-000n-mlxtdq)
