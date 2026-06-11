// Hermes envelope round-trip + dispatch: a protobuf ClientMessage frame in,
// a ServerMessage frame out, with the validator RPC payloads inside. This is
// the exact wire format the game's MbHermesClient speaks (locally against the
// emulation endpoint, in production against the gateway's Hermes).
process.env.VALIDATOR_SHARED_SECRET ??= "test-secret";

import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { HermesDispatcher } from "../hermes-ws";
import { ValidatorService } from "../service";
import { InMemoryMatchStateStore } from "../store/match-state";
import { InventoryClient, resolveInventoryTransport } from "../snaps/inventory";
import { decodeMessage, encodeMessage, getProtoRegistry } from "../proto";
import type { ValidatorConfig } from "../types";

const GOLDEN = join(import.meta.dir, "..", "..", "..", "..", "game", "tests", "golden", "engine_swipe_golden.json");

const baseConfig: ValidatorConfig = {
  sharedSecret: process.env.VALIDATOR_SHARED_SECRET!,
  matchSessionTTL: 3600,
  port: 5555,
  grpcPort: 8081,
  snapserGatewayUrl: "https://gateway.snapser.com/c4n1awfs",
};

const PLAYER = "hermes-player";
const CALLER = { "auth-type": "user", "user-id": PLAYER };
const SERVICE_PATH = "/moveborne.validator.v1.ValidatorService";

const MESSAGE_TYPE_SNAP_API_PROXY = 4;
const MESSAGE_TYPE_ERROR = 5;

function makeDispatcher(): HermesDispatcher {
  const store = new InMemoryMatchStateStore();
  const inventory = new InventoryClient(resolveInventoryTransport(baseConfig));
  return new HermesDispatcher(new ValidatorService(store, inventory));
}

function clientFrame(mid: string, method: string, requestType: string, request: Record<string, unknown>): Uint8Array {
  const { ClientMessage, root } = getProtoRegistry();
  const payload = encodeMessage(root.lookupType(requestType), request);
  return encodeMessage(ClientMessage, {
    mid,
    message_type: MESSAGE_TYPE_SNAP_API_PROXY,
    timestamp: Math.floor(Date.now() / 1000),
    snap_api_request: { api_method: method, payload },
  });
}

function serverFrame(bytes: Uint8Array): any {
  const { ServerMessage } = getProtoRegistry();
  return decodeMessage<any>(ServerMessage, bytes);
}

describe("HermesDispatcher", () => {
  test("InitMatch + ValidateAction round-trip through the envelope", async () => {
    const { initial, steps } = await Bun.file(GOLDEN).json();
    const dispatcher = makeDispatcher();
    const { root } = getProtoRegistry();

    const initResp = serverFrame(
      await dispatcher.handleFrame(
        clientFrame("mid-1", `${SERVICE_PATH}/InitMatch`, "moveborne.validator.v1.InitMatchRequest", {
          match_id: "hm1",
          starting_state_json: JSON.stringify(initial),
          player_id: PLAYER,
          mode: "story",
        }),
        CALLER,
      ),
    );
    expect(initResp.mid).toBe("mid-1");
    expect(initResp.message_type).toBe(MESSAGE_TYPE_SNAP_API_PROXY);
    expect(initResp.api_response.is_error).toBe(false);
    const init = decodeMessage<any>(
      root.lookupType("moveborne.validator.v1.InitMatchResponse"),
      initResp.api_response.payload,
    );
    expect(init.match_id).toBe("hm1");
    expect(JSON.parse(init.current_state_json).moveIndex).toBe(initial.moveIndex);

    const step = steps[0];
    const valResp = serverFrame(
      await dispatcher.handleFrame(
        clientFrame("mid-2", `${SERVICE_PATH}/ValidateAction`, "moveborne.validator.v1.ValidateActionRequest", {
          match_id: "hm1",
          index: initial.moveIndex,
          action_json: JSON.stringify({ type: "SWIPE", payload: { direction: step.dir } }),
          state_hash: step.hash,
        }),
        CALLER,
      ),
    );
    expect(valResp.mid).toBe("mid-2");
    const val = decodeMessage<any>(
      root.lookupType("moveborne.validator.v1.ValidateActionResponse"),
      valResp.api_response.payload,
    );
    expect(val.matched).toBe(true);
    expect(val.signature.length).toBe(64);
  });

  test("service errors surface as SnapApiError with gRPC codes", async () => {
    const dispatcher = makeDispatcher();
    const resp = serverFrame(
      await dispatcher.handleFrame(
        clientFrame("mid-3", `${SERVICE_PATH}/ValidateAction`, "moveborne.validator.v1.ValidateActionRequest", {
          match_id: "missing",
          index: 0,
          action_json: "{}",
          state_hash: "x",
        }),
        CALLER,
      ),
    );
    expect(resp.api_response.is_error).toBe(true);
    expect(resp.api_response.error.code).toBe(5); // NOT_FOUND
  });

  test("unknown methods mirror live Hermes: MESSAGE_TYPE_ERROR 'invalid service'", async () => {
    const dispatcher = makeDispatcher();
    const resp = serverFrame(
      await dispatcher.handleFrame(
        clientFrame("mid-4", "/nope.NopeService/Nope", "moveborne.validator.v1.CompleteMatchRequest", {
          match_id: "x",
        }),
        CALLER,
      ),
    );
    expect(resp.mid).toBe("mid-4");
    expect(resp.message_type).toBe(MESSAGE_TYPE_ERROR);
    expect(resp.error.error_message).toBe("invalid service");
  });

  test("BYOSnap-id service aliases dispatch to the same handlers", async () => {
    const { initial } = await Bun.file(GOLDEN).json();
    const dispatcher = makeDispatcher();
    for (const alias of ["byosnap-validator.ValidatorService", "byosnapvalidator.ValidatorService"]) {
      const resp = serverFrame(
        await dispatcher.handleFrame(
          clientFrame(`mid-${alias}`, `/${alias}/InitMatch`, "moveborne.validator.v1.InitMatchRequest", {
            match_id: `alias-${alias}`,
            starting_state_json: JSON.stringify(initial),
            player_id: PLAYER,
            mode: "story",
          }),
          CALLER,
        ),
      );
      expect(resp.api_response.is_error).toBe(false);
    }
  });
});
