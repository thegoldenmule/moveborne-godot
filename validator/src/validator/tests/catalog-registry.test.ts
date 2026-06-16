import { describe, it, expect, beforeEach } from "bun:test";
import { RemoteConfigClient } from "../snaps/remote-config";
import {
  loadCatalog,
  refreshCatalog,
  currentVersion,
  getCatalogAt,
  getLevelAt,
  getOrderedLevelIdsAt,
  hasVersion,
  retain,
  release,
  __resetCatalogForTests,
} from "../story/catalog";

function makeCatalog(version: number) {
  return {
    catalog_version: version,
    worlds: [
      {
        id: "w1",
        name: "W1",
        order: 0,
        levels: [
          {
            id: "w1_l1",
            order: 0,
            scenario_id: 0,
            name: "L1",
            goals: [
              { type: "points", threshold: 1, time_limit_s: null },
              { type: "points", threshold: 2, time_limit_s: null },
              { type: "max_tile", threshold: 64, time_limit_s: null },
            ],
            rewards: { complete: { coins: 1 }, per_star: [{ coins: 1 }, { coins: 1 }, { coins: 1 }] },
          },
        ],
      },
    ],
  };
}

/** An internal-transport client whose current payload can be swapped to simulate
 *  a Remote Config publish between fetches. */
function mutableClient() {
  let cur: unknown = null;
  const fetchFn = async () => new Response(JSON.stringify({ config: { story_catalog: cur } }), { status: 200 });
  const c = new RemoteConfigClient({ kind: "internal", baseUrl: "http://rc", header: "h" }, fetchFn as any);
  return { client: c, publish: (cat: unknown) => { cur = cat; } };
}

beforeEach(() => __resetCatalogForTests());

describe("loadCatalog", () => {
  it("remote happy path populates the registry + current", async () => {
    const { client, publish } = mutableClient();
    publish(makeCatalog(3));
    await loadCatalog(client, 1);
    expect(currentVersion()).toBe(3);
    expect(getLevelAt(3, "w1_l1")?.name).toBe("L1");
    expect(getOrderedLevelIdsAt(3)).toEqual(["w1_l1"]);
    expect(getCatalogAt(3)?.catalog_version).toBe(3);
  });

  it("rejects an invalid remote payload (does not adopt)", async () => {
    const { client, publish } = mutableClient();
    publish({ catalog_version: 0, worlds: [] }); // version < 1 is invalid
    await expect(loadCatalog(client, 1)).rejects.toThrow();
    expect(hasVersion(0)).toBe(false);
  });

  it("disabled transport falls back to the committed file", async () => {
    const c = new RemoteConfigClient({ kind: "disabled" });
    await loadCatalog(c, 1);
    expect(currentVersion()).toBeGreaterThanOrEqual(1);
    expect(getLevelAt(currentVersion(), "w1_l1")).toBeTruthy();
  });
});

describe("version registry — per-match pin, no wipe", () => {
  it("retains an old version while a match references it; evicts on release; never evicts current", async () => {
    const { client, publish } = mutableClient();
    publish(makeCatalog(1));
    await loadCatalog(client, 1);
    expect(currentVersion()).toBe(1);

    retain(1); // a match pins v1

    publish(makeCatalog(2)); // designer publishes a new catalog
    const r = await refreshCatalog();
    expect(r).toEqual({ version: 2, source: expect.any(String), ok: true });
    expect(currentVersion()).toBe(2);

    // v1 is still gradable because a match holds it.
    expect(hasVersion(1)).toBe(true);
    expect(getLevelAt(1, "w1_l1")).toBeTruthy();

    release(1); // the match ends
    expect(hasVersion(1)).toBe(false); // evicted — unreferenced and not current
    expect(hasVersion(2)).toBe(true); // current is never evicted
  });

  it("a failed refresh keeps the last-known-good", async () => {
    const failing = new RemoteConfigClient(
      { kind: "internal", baseUrl: "http://rc", header: "h" },
      (async () => new Response("boom", { status: 500 })) as any,
    );
    // seed v1 via the disabled fallback, then point the module client at a failing one
    const { client, publish } = mutableClient();
    publish(makeCatalog(1));
    await loadCatalog(client, 1);
    expect(currentVersion()).toBe(1);
    // simulate the live client now failing
    await loadCatalog(failing, 0).catch(() => {}); // resets client_ but current stays
    const r = await refreshCatalog();
    expect(r.ok).toBe(false);
    expect(currentVersion()).toBe(1); // unchanged
  });
});
