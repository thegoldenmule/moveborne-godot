// Story path through the real ValidatorService with mocked Storage/Inventory
// s2s transports: level binding at init, the fresh-state guard, grading +
// progress persistence + grant on CompleteMatch, the idempotency latch, and
// the watermark semantics across replays.
process.env.VALIDATOR_SHARED_SECRET ??= "test-secret";

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import type { SynchronizedGameState } from "@spyre-io/moveborne-logic";
import { GrpcStatus, ServiceError, ValidatorService } from "../service";
import { InMemoryMatchStateStore } from "../store/match-state";
import { InventoryClient } from "../snaps/inventory";
import { StorageClient, STORY_PROGRESS_KEY } from "../snaps/storage";
import type { StoredMatch } from "../types";
import type { StoryProgress, StoryResult } from "../story/types";

const GOLDEN = join(import.meta.dir, "..", "..", "..", "..", "game", "tests", "golden", "engine_swipe_golden.json");
const PLAYER = "player-1";
const USER_HEADERS = { "auth-type": "user", "user-id": PLAYER };

/** In-memory fake of the Storage snap blob API (GET 404-when-missing / PUT). */
function fakeStorage(blobs: Map<string, unknown>, opts: { failPut?: boolean } = {}) {
  const fetchFn = (async (url: unknown, init?: RequestInit) => {
    const path = String(url);
    const key = path.split("/").pop()!;
    if (!init || init.method === "GET") {
      if (!blobs.has(key)) return new Response("not found", { status: 404 });
      return Response.json({ value: blobs.get(key), cas: "1" });
    }
    if (init.method === "PUT") {
      if (opts.failPut) return new Response("boom", { status: 500 });
      blobs.set(key, (JSON.parse(String(init.body)) as { value: unknown }).value);
      return Response.json({});
    }
    return new Response("unexpected", { status: 500 });
  }) as unknown as typeof fetch;
  return new StorageClient({ kind: "internal", baseUrl: "http://service-storage:8090", header: "h" }, fetchFn);
}

function fakeInventory(granted: Record<string, number>) {
  const fetchFn = (async (url: unknown, init?: RequestInit) => {
    const currency = String(url).split("/").pop()!;
    const delta = Number((JSON.parse(String(init?.body)) as { delta_64: string }).delta_64);
    granted[currency] = (granted[currency] ?? 0) + delta;
    return Response.json({ previous_balance_64: "0", current_balance_64: String(granted[currency]) });
  }) as unknown as typeof fetch;
  return new InventoryClient({ kind: "internal", baseUrl: "http://service-inventory:8090", header: "h" }, fetchFn);
}

/** A settled story match parked directly in the store (bypasses init so tests
 *  can grade arbitrary final states the engine would have built move-by-move). */
function storedStoryMatch(
  matchId: string,
  levelId: string,
  score: number,
  tileValues: number[],
  elapsedMs = 30_000,
): StoredMatch {
  const current_state = {
    score,
    moveIndex: 5,
    board: { size: 4, tiles: tileValues.map((value, i) => ({ value, position: { row: 0, col: i } })) },
  } as unknown as SynchronizedGameState;
  return {
    match_id: matchId,
    current_state,
    player_id: PLAYER,
    mode: "story",
    level_id: levelId,
    created_at: Date.now() - elapsedMs,
    last_action_at: Date.now(),
    action_count: 5,
    state_history: new Map(),
    rewards_granted: false,
  };
}

async function golden() {
  return await Bun.file(GOLDEN).json();
}

describe("story InitMatch", () => {
  test("binds a known level; rejects an unknown level_id", async () => {
    const { initial } = await golden();
    const service = new ValidatorService(new InMemoryMatchStateStore(), fakeInventory({}), fakeStorage(new Map()));
    await service.initMatch(
      { match_id: "s1", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story", level_id: "w1_l1" },
      USER_HEADERS,
    );
    expect(
      service.initMatch(
        { match_id: "s2", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story", level_id: "nope" },
        USER_HEADERS,
      ),
    ).rejects.toThrow(ServiceError);
  });

  test("fresh-state guard: pre-scored / pre-merged / advanced states are rejected", async () => {
    const { initial } = await golden();
    const service = new ValidatorService(new InMemoryMatchStateStore(), fakeInventory({}), fakeStorage(new Map()));
    const attempts = [
      { ...initial, score: 5000 },
      { ...initial, moveIndex: 12 },
      { ...initial, board: { size: 4, tiles: [{ value: 1024, position: { row: 0, col: 0 } }] } },
    ];
    for (const state of attempts) {
      try {
        await service.initMatch(
          { match_id: "s3", starting_state_json: JSON.stringify(state), player_id: PLAYER, mode: "story", level_id: "w1_l1" },
          USER_HEADERS,
        );
        expect.unreachable("should have rejected a non-fresh story start");
      } catch (e) {
        expect((e as ServiceError).code).toBe(GrpcStatus.INVALID_ARGUMENT);
      }
    }
    // The same states are fine WITHOUT a level (infinite/dev paths unchanged).
    await service.initMatch(
      { match_id: "s4", starting_state_json: JSON.stringify({ ...initial, score: 5000 }), player_id: PLAYER, mode: "infinite" },
      USER_HEADERS,
    );
  });
});

describe("story CompleteMatch", () => {
  test("grades, persists progress, grants, and returns story_result_json", async () => {
    const blobs = new Map<string, unknown>();
    const granted: Record<string, number> = {};
    const store = new InMemoryMatchStateStore();
    const service = new ValidatorService(store, fakeInventory(granted), fakeStorage(blobs));
    // w1_l1 goals: points 240, points 480, max_tile 64 → 3 stars.
    await store.set("c1", storedStoryMatch("c1", "w1_l1", 700, [2, 64]), 3600);

    const resp = await service.completeMatch({ match_id: "c1" }, USER_HEADERS);
    // complete 30 + tiers 12+24+36 = 102 coins.
    expect(resp.rewards).toEqual({ coins: "102" });
    expect(resp.granted).toBe(true);
    expect(resp.balances.coins).toBe("102");

    const story = JSON.parse(resp.story_result_json) as StoryResult;
    expect(story).toMatchObject({
      level_id: "w1_l1",
      stars: 3,
      new_stars: 3,
      next_level_id: "w1_l2",
      unlocked: true,
    });
    expect(story.goals.length).toBe(3);

    const blob = blobs.get(STORY_PROGRESS_KEY) as StoryProgress;
    expect(blob.levels["w1_l1"]).toMatchObject({ stars: 3, rewarded_stars: 3, best_score: 700 });
    expect(blob.next_level_id).toBe("w1_l2");
  });

  test("duplicate completion latches: no second grant, no progress rewrite", async () => {
    const blobs = new Map<string, unknown>();
    const granted: Record<string, number> = {};
    const store = new InMemoryMatchStateStore();
    const service = new ValidatorService(store, fakeInventory(granted), fakeStorage(blobs));
    await store.set("c2", storedStoryMatch("c2", "w1_l1", 700, [2, 64]), 3600);

    await service.completeMatch({ match_id: "c2" }, USER_HEADERS);
    const second = await service.completeMatch({ match_id: "c2" }, USER_HEADERS);
    expect(second.granted).toBe(false);
    expect(second.rewards).toEqual({});
    expect(second.story_result_json).toBe("");
    expect(granted.coins).toBe(102); // exactly one grant
  });

  test("improving replay grants only the newly earned tier", async () => {
    const blobs = new Map<string, unknown>();
    const granted: Record<string, number> = {};
    const store = new InMemoryMatchStateStore();
    const service = new ValidatorService(store, fakeInventory(granted), fakeStorage(blobs));
    // First run: 2 stars (no 64 tile).
    await store.set("c3", storedStoryMatch("c3", "w1_l1", 700, [2, 4]), 3600);
    const first = await service.completeMatch({ match_id: "c3" }, USER_HEADERS);
    expect(first.rewards).toEqual({ coins: String(30 + 12 + 24) });
    // Replay: 3 stars → only per_star[2].
    await store.set("c4", storedStoryMatch("c4", "w1_l1", 900, [2, 64]), 3600);
    const second = await service.completeMatch({ match_id: "c4" }, USER_HEADERS);
    expect(second.rewards).toEqual({ coins: "36" });
    const story = JSON.parse(second.story_result_json) as StoryResult;
    expect(story.new_stars).toBe(1);
    // Worse third run: nothing new.
    await store.set("c5", storedStoryMatch("c5", "w1_l1", 100, [2, 4]), 3600);
    const third = await service.completeMatch({ match_id: "c5" }, USER_HEADERS);
    expect(third.rewards).toEqual({});
    expect((blobs.get(STORY_PROGRESS_KEY) as StoryProgress).levels["w1_l1"]!.stars).toBe(3);
  });

  test("timed goal fails when the match settles past the limit", async () => {
    const blobs = new Map<string, unknown>();
    const store = new InMemoryMatchStateStore();
    const service = new ValidatorService(store, fakeInventory({}), fakeStorage(blobs));
    // w1_l3 goal 3 is points 320 within 180s; settle at ~10 minutes.
    await store.set("c6", storedStoryMatch("c6", "w1_l3", 700, [2, 4], 600_000), 3600);
    const resp = await service.completeMatch({ match_id: "c6" }, USER_HEADERS);
    const story = JSON.parse(resp.story_result_json) as StoryResult;
    expect(story.stars).toBe(2); // both untimed points goals met, timed one missed
    expect(story.goals[2]!.met).toBe(false);
  });

  test("progress write failure withholds the grant (watermark gates rewards)", async () => {
    const granted: Record<string, number> = {};
    const store = new InMemoryMatchStateStore();
    const service = new ValidatorService(
      store,
      fakeInventory(granted),
      fakeStorage(new Map(), { failPut: true }),
    );
    await store.set("c7", storedStoryMatch("c7", "w1_l1", 700, [2, 64]), 3600);
    const resp = await service.completeMatch({ match_id: "c7" }, USER_HEADERS);
    expect(resp.granted).toBe(false);
    expect(resp.rewards).toEqual({});
    expect(granted).toEqual({});
    // The grade itself is still reported (the client shows stars; they re-earn
    // rewards on a future improving run since the watermark never landed).
    const story = JSON.parse(resp.story_result_json) as StoryResult;
    expect(story.stars).toBe(3);
    expect(story.rewards).toEqual({});
  });

  test("story without a level grants nothing (catalog replaced the old table)", async () => {
    const { initial } = await golden();
    const granted: Record<string, number> = {};
    const service = new ValidatorService(new InMemoryMatchStateStore(), fakeInventory(granted), fakeStorage(new Map()));
    await service.initMatch(
      { match_id: "c8", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    const resp = await service.completeMatch({ match_id: "c8" }, USER_HEADERS);
    expect(resp.rewards).toEqual({});
    expect(resp.story_result_json).toBe("");
    expect(granted).toEqual({});
  });
});
