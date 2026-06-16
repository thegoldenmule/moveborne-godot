// The story init version handshake (pinVersion) through the real
// ValidatorService: the client's catalog_version is reconciled with the
// validator's current version, and the match is pinned to the agreed one.
process.env.VALIDATOR_SHARED_SECRET ??= "test-secret";

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { GrpcStatus, ServiceError, ValidatorService } from "../service";
import { InMemoryMatchStateStore } from "../store/match-state";
import { InventoryClient } from "../snaps/inventory";
import { StorageClient } from "../snaps/storage";
import { currentVersion } from "../story/catalog";

const GOLDEN = join(import.meta.dir, "..", "..", "..", "..", "game", "tests", "golden", "engine_swipe_golden.json");
const PLAYER = "player-1";
const USER_HEADERS = { "auth-type": "user", "user-id": PLAYER };

function service() {
  return new ValidatorService(
    new InMemoryMatchStateStore(),
    new InventoryClient({ kind: "disabled" }),
    new StorageClient({ kind: "disabled" }),
  );
}

describe("story init version handshake", () => {
  test("client version == current → pins it and echoes the agreed version", async () => {
    const { initial } = await Bun.file(GOLDEN).json();
    const v = currentVersion();
    const svc = service();
    const resp = await svc.initMatch(
      { match_id: "h1", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story", level_id: "w1_l1", catalog_version: v },
      USER_HEADERS,
    );
    expect(resp.catalog_version).toBe(v);
  });

  test("client sends no version (0) → pins current (older client / no handshake)", async () => {
    const { initial } = await Bun.file(GOLDEN).json();
    const v = currentVersion();
    const svc = service();
    const resp = await svc.initMatch(
      { match_id: "h2", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story", level_id: "w1_l1", catalog_version: 0 },
      USER_HEADERS,
    );
    expect(resp.catalog_version).toBe(v);
  });

  test("client version != current (cannot converge) → FAILED_PRECONDITION catalog_version_mismatch", async () => {
    const { initial } = await Bun.file(GOLDEN).json();
    const ahead = currentVersion() + 1; // a version the validator can't reach (disabled transport re-reads the same committed file)
    const svc = service();
    try {
      await svc.initMatch(
        { match_id: "h3", starting_state_json: JSON.stringify(initial), player_id: PLAYER, mode: "story", level_id: "w1_l1", catalog_version: ahead },
        USER_HEADERS,
      );
      expect.unreachable("should reject a catalog version it cannot agree on");
    } catch (e) {
      expect((e as ServiceError).code).toBe(GrpcStatus.FAILED_PRECONDITION);
      expect((e as ServiceError).message).toContain("catalog_version_mismatch");
    }
  });

  test("non-story init ignores catalog_version (resp 0)", async () => {
    const { initial } = await Bun.file(GOLDEN).json();
    const svc = service();
    const resp = await svc.initMatch(
      { match_id: "h4", starting_state_json: JSON.stringify({ ...initial, score: 5000 }), player_id: PLAYER, mode: "infinite", catalog_version: 999 },
      USER_HEADERS,
    );
    expect(resp.catalog_version).toBe(0);
  });
});
