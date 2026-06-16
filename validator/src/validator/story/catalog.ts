/**
 * The story catalog at RUNTIME. Source of truth in production is the Snapser
 * Remote Config app-config (key "story_catalog"), pulled over s2s at boot and
 * refreshed on a TTL — the catalog is NOT bundled in the validator image (see
 * the ADR superseding the bundled-image clause of ADR-23). The committed
 * validator/content/story_catalog.json is the publish seed and the dev/test
 * fallback (used only when the Remote Config transport is disabled).
 *
 * Per-match version PINNING: a story match is graded against the catalog_version
 * it was initialized with for its whole life. We keep a registry of versions and
 * ref-count active matches (retain/release), evicting an old version only when
 * it is unreferenced AND not the current version — a publish mid-session never
 * changes an in-flight match's grading basis (no wipe).
 *
 * The classic accessors (getCatalog/getLevel/getOrderedLevelIds/validateCatalog)
 * operate on the CURRENT version and stay synchronous: if nothing is loaded yet
 * they lazily read the committed fallback (present in dev/tests; absent in the
 * image, where loadCatalog() must have run first or they throw).
 */

import { readFileSync } from "node:fs";
import type { StoryCatalog, StoryLevel } from "./types";
import type { RemoteConfigClient } from "../snaps/remote-config";

const LOCAL_FALLBACK = new URL("../../../content/story_catalog.json", import.meta.url);
const TTL_MS = 5 * 60 * 1000;

type Indexed = { catalog: StoryCatalog; levelsById: Map<string, StoryLevel>; orderedIds: string[] };

const versions = new Map<number, Indexed>(); // retained while referenced; `current` is never evicted
const refs = new Map<number, number>(); // catalog_version -> active-match count
let current = 0;
let loadedAt = 0;
let client_: RemoteConfigClient | null = null;
let refreshing: Promise<void> | null = null;

function index(c: StoryCatalog): Indexed {
  const ordered = [...c.worlds]
    .sort((a, b) => a.order - b.order)
    .flatMap((w) => [...w.levels].sort((a, b) => a.order - b.order));
  return { catalog: c, levelsById: new Map(ordered.map((l) => [l.id, l])), orderedIds: ordered.map((l) => l.id) };
}

/** Register a version (validating it first) and make it current. Never evicts. */
function adopt(c: StoryCatalog): void {
  validateCatalog(c);
  if (!versions.has(c.catalog_version)) versions.set(c.catalog_version, index(c));
  current = c.catalog_version;
  loadedAt = Date.now();
}

/** Read the committed fallback synchronously (dev/tests). Throws if absent. */
function loadCommittedSync(): StoryCatalog {
  return JSON.parse(readFileSync(LOCAL_FALLBACK, "utf8")) as StoryCatalog;
}

/** Resolve the current version, lazily loading the committed fallback if nothing
 *  has been loaded yet, and firing a background TTL refresh when stale. Throws a
 *  clear error if no catalog is available at all (production cold start before
 *  the Remote Config pull completes). */
function live(): number {
  if (current === 0) {
    try {
      adopt(loadCommittedSync());
    } catch (e) {
      throw new Error("story catalog not loaded — call loadCatalog() at boot (no Remote Config result yet)");
    }
  }
  if (client_ && refreshing === null && Date.now() - loadedAt > TTL_MS) {
    refreshing = refreshCatalog().then(() => {}).finally(() => {
      refreshing = null;
    });
  }
  return current;
}

// ── accessors (current version) ──────────────────────────────────────────────

export function getCatalog(): StoryCatalog {
  return versions.get(live())!.catalog;
}
export function getLevel(levelId: string): StoryLevel | undefined {
  return versions.get(live())!.levelsById.get(levelId);
}
export function getOrderedLevelIds(): string[] {
  return versions.get(live())!.orderedIds;
}

// ── accessors (pinned version — grading reads these) ─────────────────────────

export function currentVersion(): number {
  return live();
}
export function hasVersion(v: number): boolean {
  return versions.has(v);
}
export function getCatalogAt(v: number): StoryCatalog | undefined {
  return versions.get(v)?.catalog;
}
export function getLevelAt(v: number, levelId: string): StoryLevel | undefined {
  return versions.get(v)?.levelsById.get(levelId);
}
export function getOrderedLevelIdsAt(v: number): string[] {
  return versions.get(v)?.orderedIds ?? [];
}

// ── ref-counting (no-wipe retention) ─────────────────────────────────────────

export function retain(v: number): void {
  refs.set(v, (refs.get(v) ?? 0) + 1);
}
export function release(v: number): void {
  const n = (refs.get(v) ?? 0) - 1;
  if (n > 0) {
    refs.set(v, n);
    return;
  }
  refs.delete(v);
  if (v !== current) versions.delete(v); // evict only when unreferenced AND not current
}

// ── load / refresh ───────────────────────────────────────────────────────────

async function fetchOnce(client: RemoteConfigClient): Promise<{ catalog: StoryCatalog; source: string }> {
  if (client.enabled) {
    const raw = await client.fetchStoryCatalog();
    if (raw != null) return { catalog: raw as StoryCatalog, source: `remote-config(${client.transportKind})` };
  }
  // Disabled transport (local dev/tests): the committed file IS the catalog.
  const f = Bun.file(LOCAL_FALLBACK);
  return { catalog: (await f.json()) as StoryCatalog, source: "committed-fallback" };
}

/** Boot load. Retries with backoff until the FIRST good load (cold start has no
 *  cache). A caller that does not want to block forever can pass maxAttempts. */
export async function loadCatalog(client: RemoteConfigClient, maxAttempts = Number.POSITIVE_INFINITY): Promise<void> {
  client_ = client;
  for (let attempt = 0; current === 0; attempt++) {
    try {
      const { catalog, source } = await fetchOnce(client);
      adopt(catalog);
      console.log(`📖 Story catalog loaded (version ${catalog.catalog_version}, source ${source})`);
      return;
    } catch (e) {
      if (attempt + 1 >= maxAttempts) throw e;
      const backoff = Math.min(30_000, 500 * 2 ** attempt);
      console.warn(`story catalog load failed (attempt ${attempt + 1}); retrying in ${backoff}ms: ${e}`);
      await Bun.sleep(backoff);
    }
  }
}

/** On-demand / TTL refresh. A failure or invalid payload keeps the
 *  last-known-good (current is untouched). Returns the resulting state. */
export async function refreshCatalog(): Promise<{ version: number; source: string; ok: boolean }> {
  if (!client_) return { version: current, source: "none", ok: false };
  try {
    const { catalog, source } = await fetchOnce(client_);
    adopt(catalog);
    return { version: catalog.catalog_version, source, ok: true };
  } catch (e) {
    // Reset the TTL clock even on failure so a sustained Remote Config outage
    // doesn't re-fire a background refresh on every access (one per TTL, not a
    // storm); last-known-good keeps serving meanwhile.
    loadedAt = Date.now();
    console.warn(`story catalog refresh kept last-known-good (version ${current}): ${e}`);
    return { version: current, source: "last-known-good", ok: false };
  }
}

/** The version currently serving new matches + when it was loaded (status). */
export function loadedInfo(): { version: number; loadedAt: number; retainedVersions: number } {
  return { version: current, loadedAt, retainedVersions: versions.size };
}

// ── validation (unchanged contract) ──────────────────────────────────────────

/** Sanity-check a catalog shape; throws with every problem found. Called inside
 *  adopt() with an explicit catalog (so it never recurses into live()), and
 *  with no argument it validates the current loaded catalog (tests/boot). */
export function validateCatalog(c?: StoryCatalog): void {
  const cat = c ?? getCatalog();
  const problems: string[] = [];
  if (!Number.isInteger(cat.catalog_version) || cat.catalog_version < 1) {
    problems.push("catalog_version must be a positive integer");
  }
  const ids = new Set<string>();
  for (const world of cat.worlds ?? []) {
    for (const level of world.levels ?? []) {
      const tag = `${world.id}/${level.id}`;
      if (ids.has(level.id)) problems.push(`${tag}: duplicate level id`);
      ids.add(level.id);
      if (!Number.isInteger(level.scenario_id) || level.scenario_id < 0) {
        problems.push(`${tag}: bad scenario_id`);
      }
      if (!Array.isArray(level.goals) || level.goals.length !== 3) {
        problems.push(`${tag}: must have exactly 3 goals`);
        continue;
      }
      for (const goal of level.goals) {
        if (goal.type !== "points" && goal.type !== "max_tile") {
          problems.push(`${tag}: bad goal type '${goal.type}'`);
        }
        if (!(goal.threshold > 0)) problems.push(`${tag}: goal threshold must be > 0`);
        if (goal.time_limit_s !== null && !(goal.time_limit_s > 0)) {
          problems.push(`${tag}: time_limit_s must be null or > 0`);
        }
      }
      if (!Array.isArray(level.rewards?.per_star) || level.rewards.per_star.length !== 3) {
        problems.push(`${tag}: rewards.per_star must have exactly 3 entries`);
      }
    }
  }
  if (problems.length > 0) {
    throw new Error(`story catalog invalid:\n  ${problems.join("\n  ")}`);
  }
}

/** Test/maintenance hook: drop all loaded state so the next access reloads. */
export function __resetCatalogForTests(): void {
  versions.clear();
  refs.clear();
  current = 0;
  loadedAt = 0;
  client_ = null;
  refreshing = null;
}
