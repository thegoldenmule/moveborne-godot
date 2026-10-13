# Testing plan — Story catalog from Remote Config — single committed source, validator pulls at runtime, editor sync/publish helper

**Status:** ready

## Planned
_None._

## Passed
- resolveRemoteConfigTransport: internal when remoteConfigInternalUrl + internalHeader set; api-key when only snapserApiKey set; disabled when neither (mirrors storage transport selection). Trailing slashes stripped from baseUrl.
- RemoteConfigClient.fetchStoryCatalog (injected fetch): happy path returns config.story_catalog; sends `Gateway` header for internal and `Api-Key` for api-key; returns null when disabled or when the story_catalog key is absent; throws on non-200.
- loadCatalog: remote happy path populates the cache + orderedLevels/levelsById and logs version+source 'remote-config'; getCatalog/getLevel/getOrderedLevelIds then return correct data.
- loadCatalog rejects a malformed/empty remote payload (validateCatalog throws) and does NOT populate the cache — grading cannot proceed on bad data.
- loadCatalog disabled transport (local dev) falls back to the committed content/story_catalog.json and loads it (source 'committed-fallback').
- getCatalog/getLevel called BEFORE loadCatalog throws a clear 'not loaded' error (no silent empty catalog).
- Grading still works end-to-end after boot load: a story CompleteMatch grades stars from the cache-loaded catalog identically to the previous bundled-import behavior (service.ts getCatalog/getLevel unchanged).
- Image does not bundle the catalog: building the validator image with content/story_catalog.json .dockerignored succeeds (no compile-time import), and the running container has no embedded catalog file.
- Deployed validator pulls from Remote Config: with the remote-config s2s transport configured, the container boots, fetches app-config v1, and logs the live catalog_version; a story match grades correctly against the live catalog.
- tools/sync-catalog.ts regenerates game/story/story_catalog.json byte-identical to the committed canonical; verify_story_catalog.gd PASSES afterward (baked == committed).
- tools/story-appconfig.ts verify still passes when the live config matches the committed catalog and fails (non-zero) on a deliberate mismatch; the new `status` command reports catalog_version for committed / deployed-validator / live.
- Editor sync panel: 'Copy publish payload' places exactly {"story_catalog": <committed>} on the clipboard; the sync check surfaces in-sync vs drift (and the live catalog_version) by invoking the verify tooling, with a graceful message when bun is unavailable.
- Client unaffected: with Remote Config in sync, the game still fetches + adopts the remote catalog (select_catalog: valid AND version >= baked) and the story map renders; offline still falls back to the (now generated) baked copy. No determinism/parity verifier regresses.
- Cold boot when Remote Config is unreachable: loadCatalog retries with backoff (no crash) and only marks ready after the first successful fetch; story grading reports 'catalog unavailable' until then while non-story matches keep serving. Once loaded, readiness holds.
- Serve last-known-good: after a successful load, a subsequent refresh that fails (network) or returns an invalid payload (validateCatalog throws) leaves the in-memory cache unchanged — getCatalog still returns the prior good catalog and the failure is logged; the cache is never downgraded to empty.
- TTL refresh: once loadedAt is older than the TTL, getCatalog returns the cached catalog immediately AND triggers a single background refresh (no duplicate concurrent refreshes); a successful refresh swaps in the new catalog_version on the next read.
- On-demand refresh endpoint: POST /api/story/catalog/refresh (internal/s2s-guarded) forces a refetch and returns the resulting catalog_version + source; an unauthenticated external caller is rejected. Used by ops and the editor sync panel.
- Per-match pin survives refresh: a story match initialized at catalog_version N is graded via getLevelAt(N, level_id) even after the validator adopts N+1 mid-match (TTL or publish). The grade matches what the client displayed at start, not the new version.
- Retention / no-wipe + evict: while a match holds version N (retain), N stays in the registry after `current` advances to N+1; release(N) on the match's completion/expiry evicts N. The `current` version is never evicted even at zero refs.
- Handshake equal: client_version == current -> InitMatch succeeds, response.catalog_version == current, the match is pinned + retained at that version.
- Handshake client-behind: client_version < current -> InitMatch rejected with FAILED_PRECONDITION 'catalog_version_mismatch' carrying current; the client re-fetches Remote Config (select_catalog), then a retried init succeeds at the agreed version.
- Handshake client-ahead: client_version > current -> the validator force-refreshes from Remote Config; if it converges to client_version the init succeeds, otherwise it rejects with catalog_version_mismatch (no grading on an unknown version).
- Memory bound: with no new publish, repeated TTL refreshes keep exactly one registry entry; multiple versions exist only across a publish while older matches are still live, and the registry drains back to one as those matches end.

## Failed
_None._

## References
_None._

## Child pages
_None._
