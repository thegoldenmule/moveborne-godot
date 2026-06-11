// Generates game/tests/golden/hermes_proto_golden.json: protobuf frames
// encoded by the TS side (protobufjs, the validator's encoder) for the
// GDScript verifier (game/tools/verify_hermes_proto.gd) to decode, re-encode,
// and compare byte-for-byte — proving the godobuf bindings and the validator
// agree on the wire format.
//
//   cd validator/src/validator && bun run tools/generate-hermes-golden.ts
import { join } from "node:path";
import { encodeMessage, getProtoRegistry } from "../proto";

const OUT = join(import.meta.dir, "..", "..", "..", "..", "game", "tests", "golden", "hermes_proto_golden.json");

const { ClientMessage, ServerMessage, root } = getProtoRegistry();
const InitReq = root.lookupType("moveborne.validator.v1.InitMatchRequest");
const ValResp = root.lookupType("moveborne.validator.v1.ValidateActionResponse");
const CompleteResp = root.lookupType("moveborne.validator.v1.CompleteMatchResponse");

const hex = (b: Uint8Array) => Buffer.from(b).toString("hex");

const initPayload = encodeMessage(InitReq, {
  match_id: "golden-match",
  starting_state_json: '{"score":0,"moveIndex":0,"note":"ünïcödé ✓"}',
  player_id: "golden-player",
  mode: "story",
});

const cases = {
  client_init: {
    description: "ClientMessage snap_api_request(InitMatch)",
    type: "ClientMessage",
    bytes: hex(
      encodeMessage(ClientMessage, {
        mid: "g-1",
        message_type: 4,
        timestamp: 1781200000,
        snap_api_request: {
          api_method: "/moveborne.validator.v1.ValidatorService/InitMatch",
          payload: initPayload,
        },
      }),
    ),
    expect: { mid: "g-1", message_type: 4, timestamp: 1781200000 },
    payload_expect: {
      match_id: "golden-match",
      player_id: "golden-player",
      mode: "story",
      starting_state_json: '{"score":0,"moveIndex":0,"note":"ünïcödé ✓"}',
    },
  },
  server_validate_mismatch: {
    description: "ServerMessage api_response(ValidateActionResponse mismatch)",
    type: "ServerMessage",
    bytes: hex(
      encodeMessage(ServerMessage, {
        mid: "g-2",
        message_type: 4,
        timestamp: 1781200001,
        api_response: {
          caller_method: "/moveborne.validator.v1.ValidatorService/ValidateAction",
          caller_time: 1781200001,
          payload: encodeMessage(ValResp, {
            index: 7,
            matched: false,
            state_json: '{"score":80}',
            signature: "ab".repeat(32),
          }),
          is_error: false,
        },
      }),
    ),
    payload_expect: { index: 7, matched: false, state_json: '{"score":80}' },
  },
  server_complete_maps: {
    description: "ServerMessage api_response(CompleteMatchResponse with maps)",
    type: "ServerMessage",
    bytes: hex(
      encodeMessage(ServerMessage, {
        mid: "g-3",
        message_type: 4,
        timestamp: 1781200002,
        api_response: {
          caller_method: "/moveborne.validator.v1.ValidatorService/CompleteMatch",
          caller_time: 1781200002,
          payload: encodeMessage(CompleteResp, {
            match_id: "golden-match",
            rewards: { coins: "12", souls: "1" },
            balances: { coins: "9000000000000000000" },
            granted: true,
          }),
          is_error: false,
        },
      }),
    ),
    payload_expect: {
      match_id: "golden-match",
      rewards: { coins: "12", souls: "1" },
      balances: { coins: "9000000000000000000" },
      granted: true,
    },
  },
  server_error: {
    description: "ServerMessage error (invalid service, code 500)",
    type: "ServerMessage",
    bytes: hex(
      encodeMessage(ServerMessage, {
        mid: "g-4",
        message_type: 5,
        timestamp: 1781200003,
        error: { code: 500, error_message: "invalid service" },
      }),
    ),
    expect: { mid: "g-4", message_type: 5 },
    error_expect: { code: 500, error_message: "invalid service" },
  },
};

await Bun.write(OUT, JSON.stringify({ generated_by: "validator/src/validator/tools/generate-hermes-golden.ts", cases }, null, 2));
console.log(`wrote ${OUT}`);
