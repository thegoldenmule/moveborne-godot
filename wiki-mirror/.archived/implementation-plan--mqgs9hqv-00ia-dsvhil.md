# Implementation plan — Story catalog from Remote Config — single committed source, validator pulls at runtime, editor sync/publish helper

**Status:** ready

## Steps
- [x] Validator config: add remote-config transport inputs. In types.ts add `remoteConfigInternalUrl?: string` (and reuse internalHeader/snapserApiKey/snapserGatewayUrl). In config.ts read `SNAPEND_REMOTE_CONFIG_HTTP_URL` (confirm the exact platform-injected name against the deployed snapend) into remoteConfigInternalUrl. Add APP_CONFIG_VERSION + CATALOG_KEY constants (mirror remote_config_client.gd / story-appconfig.ts).
- [x] Validator Remote Config s2s client: new validator/src/validator/snaps/remote-config.ts mirroring snaps/storage.ts — resolveRemoteConfigTransport(config) -> internal | api-key | disabled, and a RemoteConfigClient.fetchStoryCatalog() that GETs /v1/remote-config/app-config/v1 with the right headers (`Gateway` for internal, `Api-Key` for gateway), parses body.config.story_catalog, and returns it (or null when disabled/absent). Unit-testable with an injected fetch (like StorageClient).
- [x] Validator catalog loader refactor: change story/catalog.ts from a compile-time `import rawCatalog from content/story_catalog.json` module const to a runtime cache. Add `async loadCatalog(client)` that: (1) tries Remote Config via the s2s client; (2) if disabled (local dev) reads the committed file via Bun.file(); (3) runs validateCatalog and, on success, populates a module-level cache + derived orderedLevels/levelsById + logs the loaded catalog_version and source. getCatalog/getLevel/getOrderedLevelIds read the cache and throw a clear error if loadCatalog hasn't run. Keep validateCatalog signature.
- [x] Catalog version registry + retain/release: change story/catalog.ts from a single mutable cache to a Map<catalog_version, indexed-catalog>. adopt() ADDS a version without evicting older ones and sets `current`; retain(v)/release(v) ref-count active matches; release evicts a version only when unreferenced AND not current (a publish mid-session keeps old versions alive exactly as long as matches need them — no wipe). currentVersion() drives new-match pinning; getLevelAt(version,id) drives grading. With no new publish the registry holds a single version.
- [x] Wire boot load + last-known-good: in index.ts `await loadCatalog(client)` BEFORE serving, constructing RemoteConfigClient from config (replaces the top-level validateCatalog() call). Cold boot: retry with backoff until the first successful load (non-story matches serve meanwhile; story grading returns a clear 'catalog unavailable' until ready). Once loaded, the in-memory cache is authoritative and is NEVER downgraded to empty. service.ts grading (getCatalog/getLevel ~line 330) is unchanged — it reads the populated cache.
- [x] TTL refresh + on-demand endpoint: cache stores loadedAt; getCatalog lazily fires a background refreshCatalog() when the TTL has expired (configurable, e.g. 5–10 min) and returns the cached copy immediately. A refresh that fails or returns an invalid payload keeps the last-known-good (logged). Add an internal/admin route (e.g. POST /api/story/catalog/refresh, s2s/internal-guarded) that force-refreshes and returns the resulting catalog_version + source for ops + the editor sync panel.
- [x] Pin the catalog to each story match: add catalog_version to StoredMatch (store/match-state.ts) and persist it at init. CompleteMatch grading (service.ts) reads goals via getLevelAt(match.catalog_version, level_id) — NOT the global current — so a TTL/publish refresh can never change an in-flight match's grading basis. Call retain(version) at init and release(version) on CompleteMatch AND on match expiry/clear (match-state/history-store eviction paths).
- [x] Init handshake — version agreement: add `catalog_version` to InitMatchRequest and InitMatchResponse (protos/moveborne/validator/v1/validator_messages.proto; regenerate godobuf bindings in game/net/proto/, the protobufjs descriptor, and swagger). On story init the validator runs pinVersion(client_version): equal -> pin current; client AHEAD -> force on-demand refreshCatalog() then re-check; otherwise -> reject FAILED_PRECONDITION 'catalog_version_mismatch' carrying current. The response returns the agreed/pinned catalog_version. Scope: story matches only.
- [x] Client: send + reconcile catalog_version on story init. The game includes GameState.story_catalog.catalog_version in the story InitMatch (match_controller.gd / the hermes init path). On a 'catalog_version_mismatch' rejection it re-fetches Remote Config (remote_config_client.fetch_app_config + Catalog.select_catalog), updates GameState.story_catalog + re-renders the map, then retries init once (brief 'updating levels…' state). Non-story matches send no catalog_version. Add an MbUi/headless check for the refresh-and-retry path.
- [x] Stop bundling the catalog in the image: remove the static JSON import (now runtime-loaded) and add a .dockerignore entry for content/story_catalog.json (and confirm the Dockerfile `COPY . .` no longer carries it into the image). Verify the image builds without the file and that a deployed validator with the remote-config transport configured loads the catalog from Remote Config.
- [x] Single committed source + generated baked copy: add validator/tools/sync-catalog.ts (bun) that reads validator/content/story_catalog.json and writes game/story/story_catalog.json verbatim (stable formatting matching the current committed bytes). Add a `sync:catalog` script to validator/package.json. Document that content/story_catalog.json is the only hand-edited copy; the verify_story_catalog.gd byte-compare remains the guard.
- [x] Status/verify tooling: extend validator/src/validator/tools/story-appconfig.ts with a `status` command that prints catalog_version for all three surfaces — committed file, the deployed validator's loaded catalog (via an MCP/health field or a small read), and the live Remote Config app-config — reusing the existing canonical() comparator. Keep emit + verify as-is.
- [x] Editor Catalog ⇄ Remote Config sync panel: add a panel/tab (in addons/story_map_editor or a sibling dock) showing committed-vs-live sync status + live catalog_version + a Refresh button, and a 'Copy publish payload' button that puts the {"story_catalog": <committed>} JSON on the clipboard (DisplayServer.clipboard_set) with a console-paste reminder. For the sync check, reuse the canonical TS comparator by invoking `bun tools/story-appconfig.ts verify` (OS.execute or the artgen-style bridge) and surfacing the result; fall back to a clear 'run verify in a terminal' message if bun isn't available.
- [x] Record the superseding ADR: a new decision-record under the ADRs TOC that amends ADR-23 (mqbfd5mc) — Remote Config is the validator's runtime source of truth; the committed file is the publish seed + dev/test fallback and is not bundled in the image. Note consequences (boot dependency on Remote Config, the chosen refresh + startup-failure policies, drift surfaced by the status tool).
- [x] Tests + docs: bun tests for resolveRemoteConfigTransport (internal/api-key/disabled), fetchStoryCatalog (injected fetch: happy path, missing story_catalog key, non-200), and loadCatalog (remote happy path, remote-invalid -> reject, disabled -> committed-file fallback, cache read before load -> throws). Update verify_story_catalog.gd if needed (still byte-compares). Update validator/README.md + CLAUDE.md content-pipeline notes (remote pull, sync:catalog, status command, manual publish).

## Data models & interfaces
```typescript
// validator/src/validator/snaps/remote-config.ts (NEW) — mirrors snaps/storage.ts transport selection
import type { ValidatorConfig } from "../types";

export const APP_CONFIG_VERSION = "v1";
export const CATALOG_KEY = "story_catalog";

export type RemoteConfigTransport =
  | { kind: "internal"; baseUrl: string; header: string }
  | { kind: "api-key"; baseUrl: string; apiKey: string }
  | { kind: "disabled" };

export function resolveRemoteConfigTransport(config: ValidatorConfig): RemoteConfigTransport {
  if (config.remoteConfigInternalUrl && config.internalHeader) {
    return { kind: "internal", baseUrl: config.remoteConfigInternalUrl.replace(/\/+$/, ""), header: config.internalHeader };
  }
  if (config.snapserApiKey) {
    return { kind: "api-key", baseUrl: config.snapserGatewayUrl.replace(/\/+$/, ""), apiKey: config.snapserApiKey };
  }
  return { kind: "disabled" };
}

export class RemoteConfigClient {
  constructor(private transport: RemoteConfigTransport, private fetchFn: typeof fetch = fetch) {}
  get enabled() { return this.transport.kind !== "disabled"; }

  // Returns the parsed story_catalog object, or null when disabled/absent.
  async fetchStoryCatalog(): Promise<unknown | null> {
    if (this.transport.kind === "disabled") return null;
    const headers: Record<string, string> = this.transport.kind === "internal"
      ? { "Gateway": this.transport.header }
      : { "Api-Key": this.transport.apiKey };
    const res = await this.fetchFn(`${this.transport.baseUrl}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`, { headers });
    if (!res.ok) throw new Error(`app-config ${APP_CONFIG_VERSION}: HTTP ${res.status}`);
    const body = await res.json() as { config?: Record<string, unknown> };
    return body.config?.[CATALOG_KEY] ?? null;
  }
}
```

```bash
# Surface topology after this feature
#
#   validator/content/story_catalog.json   <-- the ONE hand-edited file (canonical)
#        |  bun run sync:catalog (tools/sync-catalog.ts)
#        v
#   game/story/story_catalog.json          <-- GENERATED, byte-verified (client baked fallback)
#
#   validator/content/story_catalog.json   --(manual console paste; emit payload)-->  Remote Config app-config v1 .story_catalog
#                                                                                              |
#   deployed validator  --(s2s GET /v1/remote-config/app-config/v1 at boot)-------------------+   (NOT bundled in the image)
#
# Drift guards:
#   verify_story_catalog.gd        : baked (generated) == committed              (byte compare)
#   tools/story-appconfig.ts verify: committed == live Remote Config            (canonical compare)
#   tools/story-appconfig.ts status: catalog_version across committed / deployed-validator / live
```

```typescript
// validator/src/validator/story/catalog.ts — version REGISTRY (story matches pin a version for their lifetime)
import type { StoryCatalog, StoryLevel } from "./types";
import { RemoteConfigClient } from "../snaps/remote-config";

const LOCAL_FALLBACK = new URL("../../../content/story_catalog.json", import.meta.url);
const TTL_MS = 5 * 60 * 1000;

type Indexed = { catalog: StoryCatalog; levelsById: Map<string, StoryLevel>; orderedIds: string[] };
const versions = new Map<number, Indexed>();   // retained while referenced; `current` is never evicted
const refs = new Map<number, number>();        // catalog_version -> active-match count
let current = 0; let loadedAt = 0; let client_: RemoteConfigClient; let refreshing: Promise<void> | null = null;

function index(c: StoryCatalog): Indexed {
  const ordered = [...c.worlds].sort((a,b)=>a.order-b.order).flatMap(w=>[...w.levels].sort((a,b)=>a.order-b.order));
  return { catalog: c, levelsById: new Map(ordered.map(l=>[l.id,l])), orderedIds: ordered.map(l=>l.id) };
}
function adopt(c: StoryCatalog): void {              // ADD a version without evicting older ones
  validateCatalog(c);
  if (!versions.has(c.catalog_version)) versions.set(c.catalog_version, index(c));
  current = c.catalog_version; loadedAt = Date.now();
}

// new STORY matches pin to current; grading reads the match's pinned version.
export function currentVersion(): number { live(); return current; }                 // live(): throws if unloaded; lazy TTL refresh
export function hasVersion(v: number): boolean { return versions.has(v); }
export function getLevelAt(v: number, id: string): StoryLevel | undefined { return versions.get(v)?.levelsById.get(id); }

export function retain(v: number): void { refs.set(v, (refs.get(v) ?? 0) + 1); }
export function release(v: number): void {           // evict only when unreferenced AND not current
  const n = (refs.get(v) ?? 0) - 1;
  if (n > 0) { refs.set(v, n); return; }
  refs.delete(v);
  if (v !== current) versions.delete(v);
}
// loadCatalog()/refreshCatalog() as before but call adopt() (which registers a version); a failed/invalid
// refresh keeps the prior `current` (last-known-good). live() lazily kicks a background refresh past TTL.
```

```typescript
// Story-match init handshake — client + validator agree on ONE catalog version, pinned for the match.
// Proto (protos/.../validator_messages.proto): InitMatchRequest += `uint32 catalog_version`;
//   InitMatchResponse += `uint32 catalog_version` (the agreed/pinned one). Regenerate godobuf + protobufjs + swagger.

// validator (routes/match.ts, story init only):
async function pinVersion(clientVersion: number): Promise<number> {
  let v = currentVersion();
  if (clientVersion === v) return v;                 // already agree
  if (clientVersion > v) {                            // client saw a newer publish — converge from the same source
    await refreshCatalog(); v = currentVersion();
    if (clientVersion === v) return v;
  }
  throw new ServiceError(GrpcStatus.FAILED_PRECONDITION, "catalog_version_mismatch", { current: v });
}
// init:     const v = await pinVersion(req.catalog_version); retain(v); stored.catalog_version = v; resp.catalog_version = v;
// grade:    const level = getLevelAt(match.catalog_version, match.level_id);  // NEVER the global current
// teardown: release(match.catalog_version)  // on CompleteMatch and on expiry/clear

// client (game): send GameState.story_catalog.catalog_version on story init; on FAILED_PRECONDITION
// "catalog_version_mismatch" -> await remote-config refresh (fetch_app_config + select_catalog), update
// GameState.story_catalog + the story map, then retry init once ('updating levels…'). Non-story matches send nothing.
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
