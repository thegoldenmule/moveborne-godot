// Service-handler tests driven by the REAL golden vectors generated from the
// TS logic dist (game/tests/golden/engine_swipe_golden.json) — never
// hand-written hashes. Covers: hash-match happy path, mismatch returning the
// authoritative state, idempotent completion, and gateway identity binding.
process.env.VALIDATOR_SHARED_SECRET ??= "test-secret";

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { computeStateHash } from "@spyre-io/moveborne-logic";
import { GrpcStatus, ServiceError, ValidatorService } from "../service";
import { InMemoryMatchStateStore } from "../store/match-state";
import { InventoryClient, resolveInventoryTransport } from "../snaps/inventory";
import { verifyValidatorSignature } from "../utils/crypto";
import type { ValidatorConfig } from "../types";

const GOLDEN = join(import.meta.dir, "..", "..", "..", "..", "game", "tests", "golden", "engine_swipe_golden.json");

const baseConfig: ValidatorConfig = {
  sharedSecret: process.env.VALIDATOR_SHARED_SECRET!,
  matchSessionTTL: 3600,
  port: 5555,
  grpcPort: 8081,
  snapserGatewayUrl: "https://gateway.snapser.com/c4n1awfs",
};

const PLAYER = "player-1";
const USER_HEADERS = { "auth-type": "user", "user-id": PLAYER };
const OTHER_HEADERS = { "auth-type": "user", "user-id": "someone-else" };

async function golden() {
  return await Bun.file(GOLDEN).json();
}

function makeService(): ValidatorService {
  const store = new InMemoryMatchStateStore();
  const inventory = new InventoryClient(resolveInventoryTransport(baseConfig));
  return new ValidatorService(store, inventory);
}

function swipe(direction: string): string {
  return JSON.stringify({ type: "SWIPE", payload: { direction } });
}

describe("ValidatorService", () => {
  test("init -> golden-hash matches across chained actions, signatures verify", async () => {
    const { initial, steps } = await golden();
    const service = makeService();

    const init = await service.initMatch(
      { match_id: "m1", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    expect(init.match_id).toBe("m1");
    expect(JSON.parse(init.current_state_json).moveIndex).toBe(initial.moveIndex);

    let index = initial.moveIndex as number;
    for (const step of steps.slice(0, 3)) {
      const resp = await service.validateAction(
        { match_id: "m1", index, action_json: swipe(step.dir), state_hash: step.hash },
        USER_HEADERS,
      );
      expect(resp.matched).toBe(true);
      expect(resp.state_json).toBe("");
      expect(
        verifyValidatorSignature(
          "m1", index, JSON.parse(swipe(step.dir)), step.hash, resp.signature, baseConfig.sharedSecret,
        ),
      ).toBe(true);
      index += step.cardDrawn ? 2 : 1;
    }
  });

  test("tampered hash -> mismatch returns the authoritative state", async () => {
    const { initial, steps } = await golden();
    const service = makeService();
    await service.initMatch(
      { match_id: "m2", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );

    const step = steps[0];
    const resp = await service.validateAction(
      { match_id: "m2", index: initial.moveIndex, action_json: swipe(step.dir), state_hash: "deadbeef" },
      USER_HEADERS,
    );
    expect(resp.matched).toBe(false);
    const authoritative = JSON.parse(resp.state_json);
    // The authoritative state is exactly the golden post-action state.
    expect(computeStateHash(authoritative)).toBe(step.hash);
    // Signature signs the validator-COMPUTED hash, not the client's claim.
    expect(
      verifyValidatorSignature(
        "m2", initial.moveIndex, JSON.parse(swipe(step.dir)), step.hash, resp.signature, baseConfig.sharedSecret,
      ),
    ).toBe(true);
  });

  test("completeMatch settles once and latches (story sans level grants nothing)", async () => {
    const { initial, steps } = await golden();
    const service = makeService();
    await service.initMatch(
      { match_id: "m3", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    const step = steps[0];
    await service.validateAction(
      { match_id: "m3", index: initial.moveIndex, action_json: swipe(step.dir), state_hash: step.hash },
      USER_HEADERS,
    );

    const first = await service.completeMatch({ match_id: "m3" }, USER_HEADERS);
    // Catalog star rewards replaced the flat story table (decision 2026-06-12);
    // a story match without a level_id grants nothing. Story-with-level paths
    // are covered in service-story.test.ts.
    expect(first.rewards).toEqual({});
    expect(first.story_result_json).toBe("");
    // No s2s credentials in tests -> grant is a logged no-op.
    expect(first.granted).toBe(false);

    const second = await service.completeMatch({ match_id: "m3" }, USER_HEADERS);
    expect(second.rewards).toEqual({});
    expect(second.granted).toBe(false);
  });

  test("completeMatch: granted reflects the actual Inventory credit, not transport availability", async () => {
    const { initial, steps } = await golden();
    const step = steps[0];

    const serviceWithInventory = (status: number, body: unknown) => {
      const fetchFn = (async () =>
        new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;
      const inventory = new InventoryClient(
        { kind: "internal", baseUrl: "http://service-inventory:8090", header: "internal-secret" },
        fetchFn,
      );
      return new ValidatorService(new InMemoryMatchStateStore(), inventory);
    };

    const play = async (service: ValidatorService, matchId: string) => {
      // pvp grants flat souls through the reward table (story rewards are
      // catalog-driven and covered in service-story.test.ts).
      await service.initMatch(
        { match_id: matchId, starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "pvp" },
        USER_HEADERS,
      );
      await service.validateAction(
        { match_id: matchId, index: initial.moveIndex, action_json: swipe(step.dir), state_hash: step.hash },
        USER_HEADERS,
      );
      return service.completeMatch({ match_id: matchId }, USER_HEADERS);
    };

    // Upstream failure (e.g. currency not provisioned in the snapend's
    // Inventory config) -> rewards reported but granted=false, no balances.
    const failed = await play(serviceWithInventory(404, { message: "currency not found" }), "m5");
    expect(failed.rewards.souls).toBe("1");
    expect(failed.balances).toEqual({});
    expect(failed.granted).toBe(false);

    // Successful credit -> granted=true with the new balance surfaced.
    const ok = await play(
      serviceWithInventory(200, { previous_balance_64: "0", current_balance_64: "8" }),
      "m6",
    );
    expect(ok.balances.souls).toBe("8");
    expect(ok.granted).toBe(true);
  });

  test("identity binding: callers that are not the match owner are rejected", async () => {
    const { initial } = await golden();
    const service = makeService();

    expect(
      service.initMatch(
        { match_id: "m4", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
        OTHER_HEADERS,
      ),
    ).rejects.toThrow(ServiceError);

    await service.initMatch(
      { match_id: "m4", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    try {
      await service.validateAction(
        { match_id: "m4", index: initial.moveIndex, action_json: swipe("down"), state_hash: "x" },
        OTHER_HEADERS,
      );
      expect.unreachable("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(ServiceError);
      expect((e as ServiceError).code).toBe(GrpcStatus.PERMISSION_DENIED);
    }

    // api-key / internal callers pass unbound (server-side tooling).
    const resp = await service.completeMatch({ match_id: "m4" }, { "auth-type": "api-key" });
    expect(resp.match_id).toBe("m4");
  });

  test("unknown match -> NOT_FOUND", async () => {
    const service = makeService();
    try {
      await service.validateAction(
        { match_id: "nope", index: 0, action_json: swipe("down"), state_hash: "x" },
        USER_HEADERS,
      );
      expect.unreachable("should have thrown");
    } catch (e) {
      expect((e as ServiceError).code).toBe(GrpcStatus.NOT_FOUND);
    }
  });

  test("re-init by a different owner is rejected (no clobber); same owner may re-init", async () => {
    const { initial } = await golden();
    const service = makeService();
    await service.initMatch(
      { match_id: "m5", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    // A different authenticated user cannot seize match m5.
    try {
      await service.initMatch(
        { match_id: "m5", starting_state_json: JSON.stringify(initial), player_id: "someone-else", mode: "story" },
        OTHER_HEADERS,
      );
      expect.unreachable("should have thrown");
    } catch (e) {
      expect((e as ServiceError).code).toBe(GrpcStatus.PERMISSION_DENIED);
    }
    // The original owner still owns it.
    const resp = await service.completeMatch({ match_id: "m5" }, USER_HEADERS);
    expect(resp.match_id).toBe("m5");
    // Same-owner re-init is allowed (the game always mints a fresh id anyway).
    await service.initMatch(
      { match_id: "m5", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
  });

  test("stale action index is rejected (proto3 omitted index decodes to 0)", async () => {
    const { initial, steps } = await golden();
    const service = makeService();
    await service.initMatch(
      { match_id: "m6", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story" },
      USER_HEADERS,
    );
    // Advance one move so current moveIndex != 0.
    const step = steps[0];
    await service.validateAction(
      { match_id: "m6", index: initial.moveIndex, action_json: swipe(step.dir), state_hash: step.hash },
      USER_HEADERS,
    );
    // A replayed/omitted index (0) no longer matches the current moveIndex.
    try {
      await service.validateAction(
        { match_id: "m6", index: 0, action_json: swipe("down"), state_hash: "x" },
        USER_HEADERS,
      );
      expect.unreachable("should have thrown");
    } catch (e) {
      expect((e as ServiceError).code).toBe(GrpcStatus.INVALID_ARGUMENT);
    }
  });
});
