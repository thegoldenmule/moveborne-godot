// Generates validator/swagger.json — the OpenAPI spec Snapser uploads on
// `snapctl byosnap publish` (it powers the API Explorer, the generated SDKs,
// and the gateway's per-route auth via x-snapser-auth-*). Keeping the spec
// here, code-defined, makes it regeneratable and pulls the version from
// package.json so it can't drift from /api/status and the deployed image.
//
//   cd validator/src/validator && bun run tools/gen-swagger.ts
//   (or, from the repo, tools/gen-protos.sh which also regenerates the SDKs)
//
// The game-facing match RPCs are gRPC over Snapser Hermes, not HTTP — they are
// described in the protos (validator/protos/) and summarized in info.description;
// only the HTTP surface (probe, status, history tooling, MCP, and the local
// Hermes-emulation upgrade) is an OpenAPI path.
import { join } from "node:path";
import pkg from "../package.json" with { type: "json" };

const GATEWAY = process.env.SNAPSER_GATEWAY_URL || "https://gateway.snapser.com/c4n1awfs";
const BASE_PATH = "/v1/byosnap-validator";

const AUTH_PUBLIC = {
  "x-snapser-auth-types": ["user", "api-key", "internal"],
  "x-snapser-auth-passthrough": true,
};
const AUTH_PRIVATE = { "x-snapser-auth-types": ["api-key", "internal"] };

const ref = (name: string) => ({ $ref: `#/components/schemas/${name}` });
const json = (schema: unknown) => ({ content: { "application/json": { schema } } });
const errorResponses = (codes: Record<string, string>) =>
  Object.fromEntries(Object.entries(codes).map(([code, description]) => [code, { description, ...json(ref("Error")) }]));

const spec = {
  openapi: "3.0.3",
  info: {
    title: "Validator Service",
    version: pkg.version,
    description:
      "Real-time game-action validation service (BYOSnap). Game-facing match RPCs " +
      "(InitMatch, ValidateAction, CompleteMatch) are a gRPC service " +
      "(moveborne.validator.v1.ValidatorService, container gRPC port 8081) defined in " +
      "validator/protos/, reached in production through the Snapser Hermes WebSocket " +
      "(MESSAGE_TYPE_SNAP_API_PROXY) and locally through the validator's own " +
      "Hermes-emulation endpoint (GET /hermes/ws?token=<player-id>, WebSocket upgrade). " +
      "The HTTP surface below carries the platform probe, status, state-history debug " +
      "tooling, and the MCP debugging endpoint.\n\n" +
      "Authentication: each operation declares `x-snapser-auth-types` (user|api-key|internal). " +
      "Operations that also set `x-snapser-auth-passthrough: true` are public — the gateway " +
      "does not require a session token. The validator binds user-context requests to the " +
      "gateway-validated User-Id header (must match player_id / the match owner); the same " +
      "binding applies to gRPC metadata.",
  },
  servers: [
    { url: GATEWAY + BASE_PATH, description: "Snapser dev snapend gateway (c4n1awfs)" },
    { url: "http://localhost:5555", description: "Local development" },
  ],
  tags: [
    { name: "Service", description: "Service info and health" },
    { name: "Match", description: "Match lifecycle and state history" },
    { name: "Realtime", description: "Hermes-envelope WebSocket (local emulation of the gateway's Hermes endpoint)" },
    { name: "Debug", description: "MCP inspection/debugging interface" },
  ],
  paths: {
    "/": {
      get: {
        tags: ["Service"],
        summary: "Service info",
        description: "Returns a human-readable summary of the service and its primary endpoints.",
        operationId: "getServiceInfo",
        responses: { "200": { description: "Service information", ...json(ref("ServiceInfo")) } },
        ...AUTH_PUBLIC,
      },
    },
    "/health": {
      get: {
        tags: ["Service"],
        summary: "Health check",
        description:
          "Liveness/readiness probe. Always returns 200 with a timestamp when the process is up. " +
          "Used as the BYOSnap readiness probe path (answered unprefixed for the platform probe).",
        operationId: "getHealth",
        responses: { "200": { description: "Service is healthy", ...json(ref("HealthResponse")) } },
        ...AUTH_PUBLIC,
      },
    },
    "/api/status": {
      get: {
        tags: ["Service"],
        summary: "Runtime status",
        description: "Reports server name, version, process uptime, the active transport, and the resolved currency-award transport.",
        operationId: "getStatus",
        responses: { "200": { description: "Runtime status", ...json(ref("StatusResponse")) } },
        ...AUTH_PUBLIC,
      },
    },
    "/api/match/init-from-history": {
      post: {
        tags: ["Match"],
        summary: "Initialize a match from a saved state history",
        description:
          "Creates a replay match from a previously saved state history. Provide either " +
          "`history_file_id` (looked up in the history store or fixtures) or inline `history_data`. " +
          "Optionally start from a specific `start_from_index`.",
        operationId: "initMatchFromHistory",
        requestBody: { required: true, ...json(ref("ValidatorInitFromHistoryRequest")) },
        responses: {
          "200": {
            description: "Match registered from history",
            ...json({
              type: "object",
              properties: {
                match_id: { type: "string" },
                state_count: { type: "integer" },
                current_move_index: { type: "integer" },
                expires_at: { type: "integer", format: "int64" },
              },
            }),
          },
          ...errorResponses({
            "400": "Validation error (missing player_id, no history source, empty/invalid history, or no state at start index)",
            "404": "History not found in store or filesystem",
            "500": "Internal error",
          }),
        },
        ...AUTH_PUBLIC,
      },
    },
    "/api/match/save-history": {
      post: {
        tags: ["Match"],
        summary: "Save a state history",
        description:
          "Persists an array of state snapshots to the history store and returns a generated id that " +
          "can later be replayed via /api/match/init-from-history.",
        operationId: "saveHistory",
        requestBody: { required: true, ...json(ref("SaveHistoryRequest")) },
        responses: {
          "200": { description: "History saved", ...json(ref("SaveHistoryResponse")) },
          ...errorResponses({ "400": "Invalid or empty states array", "500": "Internal error" }),
        },
        ...AUTH_PRIVATE,
      },
    },
    "/api/match/load-history/{id}": {
      get: {
        tags: ["Match"],
        summary: "Load a saved state history",
        description: "Returns the stored state snapshots for a previously saved history id.",
        operationId: "loadHistory",
        parameters: [
          {
            name: "id",
            in: "path",
            required: true,
            description: "History id returned by /api/match/save-history",
            schema: { type: "string" },
          },
        ],
        responses: {
          "200": { description: "History found", ...json(ref("LoadHistoryResponse")) },
          ...errorResponses({ "400": "History id is required", "404": "History not found or expired", "500": "Internal error" }),
        },
        ...AUTH_PRIVATE,
      },
    },
    "/mcp": {
      post: {
        tags: ["Debug"],
        summary: "MCP JSON-RPC endpoint",
        description:
          "Model Context Protocol (StreamableHTTP) endpoint for inspecting and debugging match state. " +
          "Exposes tools: list_matches, get_match_state, get_state_history, simulate_action, clear_match. " +
          "Requires `Accept: application/json, text/event-stream`. NOT public — keep behind authentication, " +
          "as it can mutate match state.",
        operationId: "mcpJsonRpc",
        requestBody: { required: true, ...json(ref("JsonRpcRequest")) },
        responses: {
          "200": {
            description: "JSON-RPC response (delivered as an SSE event stream)",
            content: { "text/event-stream": { schema: { type: "string" } } },
          },
        },
        ...AUTH_PRIVATE,
      },
    },
    "/hermes/ws": {
      get: {
        tags: ["Realtime"],
        summary: "Hermes-envelope WebSocket (local dev emulation)",
        description:
          "WebSocket upgrade carrying binary protobuf hermes.ClientMessage/ServerMessage frames — the same " +
          "envelope the Snapser Hermes endpoint speaks. snap_api_request payloads are dispatched to the " +
          "ValidatorService RPC handlers. The ?token= query param is the self-stamped player id. " +
          "LOCAL DEV ONLY: this route is mounted only when there is no gateway prefix; deployed, the game " +
          "uses the real gateway Hermes endpoint (wss://<gateway>/v1/hermes/ws) instead. Only partially " +
          "describable in OpenAPI.",
        operationId: "hermesWs",
        ...AUTH_PUBLIC,
        parameters: [
          {
            name: "token",
            in: "query",
            required: true,
            schema: { type: "string" },
            description: "Local self-stamped player id (the deployed Hermes endpoint takes the session token here).",
          },
        ],
        responses: {
          "101": { description: "Switching Protocols (WebSocket upgrade)" },
          "401": { description: "Missing token / gateway identity" },
        },
      },
    },
  },
  components: {
    schemas: {
      Error: {
        type: "object",
        description: "Standard error envelope returned by HTTP endpoints.",
        properties: {
          error: { type: "string", description: "Machine-readable error code", example: "VALIDATION_ERROR" },
          message: { type: "string", description: "Human-readable message" },
        },
        required: ["error", "message"],
      },
      ServiceInfo: {
        type: "object",
        properties: {
          message: { type: "string", example: "Moveborne Validator Service" },
          endpoints: {
            type: "object",
            additionalProperties: { type: "string" },
            example: {
              health: "/health",
              status: "/api/status",
              hermesWs: "/hermes/ws?token=<player-or-session>",
              grpc: ":8081 (moveborne.validator.v1.ValidatorService)",
              mcp: "/mcp",
            },
          },
        },
      },
      HealthResponse: {
        type: "object",
        properties: {
          status: { type: "string", example: "ok" },
          timestamp: { type: "integer", format: "int64", description: "Epoch milliseconds" },
        },
        required: ["status", "timestamp"],
      },
      StatusResponse: {
        type: "object",
        properties: {
          server: { type: "string", example: "validator" },
          version: { type: "string", example: pkg.version },
          uptime: { type: "number", format: "double", description: "Process uptime in seconds" },
          transport: { type: "string", example: "grpc+hermes" },
          awards: { type: "string", description: "Resolved currency-award s2s transport, or 'disabled'", example: "internal" },
        },
        required: ["server", "version", "uptime", "transport"],
      },
      Tile: {
        type: "object",
        description: "A single board cell. Shape is defined by the game logic package; extra fields are allowed.",
        additionalProperties: true,
        properties: { isEmpty: { type: "boolean" }, value: { type: "integer" } },
      },
      Board: {
        type: "object",
        description: "Game board. Extra fields from the game logic package are allowed.",
        additionalProperties: true,
        properties: { tiles: { type: "array", items: ref("Tile") } },
      },
      SynchronizedGameState: {
        type: "object",
        description:
          "Deterministic, hashable game state shared between client and validator. Defined by " +
          "@spyre-io/moveborne-logic; only the fields the validator reads are described here and " +
          "additional fields are allowed. On the wire it travels as a canonical-JSON string inside the " +
          "proto messages, so the determinism hash domain is preserved.",
        additionalProperties: true,
        properties: {
          moveIndex: { type: "integer", description: "Monotonic action index" },
          score: { type: "integer" },
          gameStatus: { type: "string", description: "e.g. IN_PROGRESS, GAME_OVER", example: "IN_PROGRESS" },
          board: ref("Board"),
          rngIndices: { type: "object", description: "Per-stream RNG consumption indices.", additionalProperties: true },
          randomSeeds: { description: "Seeds for the deterministic RNG streams.", additionalProperties: true },
        },
        required: ["moveIndex", "board", "gameStatus", "rngIndices"],
      },
      StateHistorySnapshot: {
        type: "object",
        properties: {
          moveIndex: { type: "integer" },
          timestamp: { type: "integer", format: "int64", description: "Epoch milliseconds" },
          state: ref("SynchronizedGameState"),
        },
        required: ["moveIndex", "state"],
      },
      ValidatorInitFromHistoryRequest: {
        type: "object",
        description: "Provide exactly one of history_file_id or history_data.",
        properties: {
          history_file_id: { type: "string", description: "Id of a stored/fixture history" },
          history_data: { type: "array", items: ref("StateHistorySnapshot") },
          start_from_index: { type: "integer", description: "moveIndex to start from; defaults to the last state" },
          player_id: { type: "string" },
        },
        required: ["player_id"],
      },
      SaveHistoryRequest: {
        type: "object",
        properties: { states: { type: "array", minItems: 1, items: ref("StateHistorySnapshot") } },
        required: ["states"],
      },
      SaveHistoryResponse: {
        type: "object",
        properties: { history_id: { type: "string" }, state_count: { type: "integer" } },
        required: ["history_id", "state_count"],
      },
      LoadHistoryResponse: {
        type: "object",
        properties: {
          history_id: { type: "string" },
          state_count: { type: "integer" },
          states: { type: "array", items: ref("StateHistorySnapshot") },
        },
        required: ["history_id", "state_count", "states"],
      },
      JsonRpcRequest: {
        type: "object",
        description: "JSON-RPC 2.0 request envelope used by the MCP endpoint.",
        properties: {
          jsonrpc: { type: "string", enum: ["2.0"] },
          id: { oneOf: [{ type: "string" }, { type: "integer" }] },
          method: { type: "string", example: "tools/list" },
          params: { type: "object", additionalProperties: true },
        },
        required: ["jsonrpc", "method"],
      },
    },
  },
};

// import.meta.dir = validator/src/validator/tools → ../../.. = validator/
const OUT = join(import.meta.dir, "..", "..", "..", "swagger.json");
await Bun.write(OUT, JSON.stringify(spec, null, 2) + "\n");
console.log(`wrote ${OUT} (version ${pkg.version})`);
