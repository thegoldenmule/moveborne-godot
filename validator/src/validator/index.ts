import { Server as SocketIOServer } from "socket.io";
import { Server as Engine } from "@socket.io/bun-engine";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { computeStateHash, executeAction, RandomGenerator, calculateShards } from "@spyre-io/moveborne-logic";
import { InMemoryMatchStateStore } from "./store/match-state";
import { FileSystemHistoryStore } from "./store/history-store";
import { createMatchRoutes } from "./routes/match";
import { createValidatorMCP } from "./mcp";
import { getConfig } from "./config";
import { signValidatorResponse } from "./utils/crypto";
import { verifySnapserCaller } from "./utils/snapser-auth";
import { InventoryClient, resolveInventoryTransport } from "./snaps/inventory";
import { computeMatchRewards } from "./rewards";
import type {
  CurrencyDeltas,
  CurrencyName,
  GameActionRequest,
  GameActionResponseMatch,
  GameActionResponseMismatch,
  MatchRewardsResponse,
} from "./types";

const store = new InMemoryMatchStateStore();
const historyStore = new FileSystemHistoryStore();
const config = getConfig();
const inventory = new InventoryClient(resolveInventoryTransport(config));
console.log(`💰 Currency awards: ${inventory.enabled ? `enabled (${inventory.transportKind})` : "disabled (no s2s credentials)"}`);

// The Snapser gateway forwards the full route prefix (e.g. /v1/byosnap-validator) to the
// container without stripping it. Serve all routes under this base path so they match.
// Empty for local dev (no prefix).
const BASE_PATH = (process.env.BYOSNAP_BASE_PATH || "").replace(/\/+$/, "");

const io = new SocketIOServer({
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
    credentials: true,
  },
});

const engine = new Engine({
  path: `${BASE_PATH}/socket.io/`,
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
    credentials: true,
  },
});

io.bind(engine);

io.use(async (socket, next) => {
  try {
    const { connection_id, player_id } = socket.handshake.auth;

    if (!connection_id || !player_id) {
      return next(new Error("Missing connection_id or player_id in handshake"));
    }

    const match = await store.getByConnectionId(connection_id);
    if (!match) {
      return next(new Error("MATCH_NOT_FOUND"));
    }

    if (match.player_id !== player_id) {
      return next(new Error("PLAYER_MISMATCH"));
    }

    // Bind the WS upgrade to the gateway-validated user too: the gateway checks
    // the session token on the upgrade request and forwards User-Id, same as HTTP.
    const auth = verifySnapserCaller(socket.handshake.headers, player_id);
    if (!auth.ok) {
      return next(new Error("UNAUTHORIZED"));
    }

    socket.data.match_id = match.match_id;
    socket.data.player_id = player_id;
    socket.data.connection_id = connection_id;

    next();
  } catch (error) {
    console.error("Socket authentication error:", error);
    next(new Error("AUTHENTICATION_FAILED"));
  }
});

io.on("connection", async (socket) => {
  const { match_id, player_id } = socket.data;
  console.log(`Client connected: ${socket.id} (match: ${match_id}, player: ${player_id})`);

  socket.join(match_id);

  const match = await store.get(match_id);
  if (!match) {
    socket.emit("error", { error: "MATCH_NOT_FOUND", message: "Match not found" });
    socket.disconnect();
    return;
  }

  const state_history_array = Array.from(match.state_history.entries())
    .map(([moveIndex, state]) => ({ moveIndex, state }))
    .sort((a, b) => a.moveIndex - b.moveIndex);

  socket.emit("ready", {
    match_id,
    timestamp: Date.now(),
    current_state: match.current_state,
    state_history: state_history_array,
  });

  socket.on("validate_action", async (request: GameActionRequest, callback) => {
    try {
      const { index, action, state_hash } = request;
      const { match_id } = socket.data;

      const match = await store.get(match_id);
      if (!match) {
        callback({ error: "MATCH_NOT_FOUND", message: "Match not found" });
        return;
      }

      console.log(`Validating action - state BEFORE execution:`, {
        moveIndex: match.current_state.moveIndex,
        tiles: match.current_state.board.tiles.filter(t => !t.isEmpty),
        rngIndices: match.current_state.rngIndices,
      });

      const rng = new RandomGenerator(
        match.current_state.randomSeeds,
        match.current_state.rngIndices,
      );

      const executionResult = executeAction(match.current_state, action, rng);

      if (!executionResult.success) {
        callback({
          error: "ACTION_FAILED",
          message: executionResult.error || "Action execution failed"
        });
        return;
      }

      // executionResult.newState has shards and card draw already applied
      // But score needs to be accumulated from previous state
      let newState = {
        ...executionResult.newState,
        score: executionResult.newState.score + (executionResult.scoreAdded || 0),
        rngIndices: rng.getIndices(),
        // Increment moveIndex: +1 normally, +2 when card auto-drawn (matches client behavior)
        moveIndex: index + (executionResult.cardDrawn ? 2 : 1),
      };

      // Store state in history
      match.state_history.set(newState.moveIndex, newState);

      const computedHash = computeStateHash(newState);

      const signature = signValidatorResponse(
        match_id,
        index,
        action,
        computedHash,
        config.sharedSecret,
      );

      if (computedHash === state_hash) {
        const response: GameActionResponseMatch = {
          index,
          signature,
        };

        match.current_state = newState;
        match.action_count += 1;
        match.last_action_at = Date.now();
        await store.set(match_id, match, config.matchSessionTTL);

        callback(response);
      } else {
        const response: GameActionResponseMismatch = {
          index,
          state: newState,
          signature,
        };

        match.current_state = newState;
        match.action_count += 1;
        match.last_action_at = Date.now();
        await store.set(match_id, match, config.matchSessionTTL);

        callback(response);
      }

      console.log(`Action validated: match=${match_id}, index=${index}, hash_match=${computedHash === state_hash}`);
    } catch (error) {
      console.error("Error validating action:", error);
      callback({ error: "VALIDATION_FAILED", message: "Failed to validate action" });
    }
  });

  // Match settlement. The engine has no game-over — the client's quit IS the
  // match end — so completion is an explicit, idempotent event. The client only
  // chooses WHEN to settle; rewards come from the validator's own validated
  // state via the reward table, so the grant cannot be inflated.
  socket.on("complete_match", async (_request: unknown, callback) => {
    try {
      const { match_id, player_id } = socket.data;

      const match = await store.get(match_id);
      if (!match) {
        callback({ error: "MATCH_NOT_FOUND", message: "Match not found" });
        return;
      }

      if (match.rewards_granted) {
        const response: MatchRewardsResponse = {
          match_id,
          rewards: {},
          balances: {},
          granted: false,
        };
        callback(response);
        return;
      }

      // Latch BEFORE the s2s calls so a racing duplicate completion can't
      // double-grant; a failed upstream call costs the player the award rather
      // than risking a dupe (acceptable for v1 — no retry queue).
      match.rewards_granted = true;
      await store.set(match_id, match, config.matchSessionTTL);

      const rewards = computeMatchRewards(match.mode, match.current_state);
      const balances: CurrencyDeltas = {};
      if (inventory.enabled) {
        for (const [currency, delta] of Object.entries(rewards)) {
          const result = await inventory.incrementUserCurrency(player_id, currency as CurrencyName, delta);
          if (result) {
            balances[currency as CurrencyName] = result.current_balance_64;
          }
        }
      }

      const response: MatchRewardsResponse = {
        match_id,
        rewards,
        balances,
        granted: inventory.enabled,
      };
      console.log(`Match completed: ${match_id} (mode=${match.mode}, score=${match.current_state.score})`, { rewards, balances });
      callback(response);
    } catch (error) {
      console.error("Error completing match:", error);
      callback({ error: "COMPLETION_FAILED", message: "Failed to complete match" });
    }
  });

  socket.on("disconnect", async () => {
    console.log(`Client disconnected: ${socket.id}`);
  });
});

const app = new Hono().basePath(BASE_PATH);

app.use("/*", cors({
  origin: "*",
  allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  // Include the headers the Snapser gateway forwards so browser preflights succeed.
  allowHeaders: [
    "Origin", "Content-Type", "Authorization",
    "Token", "User-Id", "App-Key", "Api-Key", "Auth-Type",
  ],
  exposeHeaders: ["Content-Length"],
  credentials: true,
}));

app.get("/health", (c) => {
  return c.json({ status: "ok", timestamp: Date.now() });
});

app.get("/api/status", (c) => {
  return c.json({
    server: "validator",
    version: "0.1.0",
    uptime: process.uptime(),
    connections: io.engine.clientsCount,
    // Which s2s transport the currency-award path resolved to (no secrets).
    awards: inventory.enabled ? inventory.transportKind : "disabled",
  });
});

app.get("/", (c) => {
  return c.json({
    message: "Moveborne Validator Service",
    endpoints: {
      health: "/health",
      status: "/api/status",
      matchInit: "/api/match/init",
      socketio: "/socket.io/",
    },
  });
});

const matchRoutes = createMatchRoutes(store, historyStore);
app.route("/api/match", matchRoutes);

const mcpServer = createValidatorMCP(store);
app.route("/mcp", mcpServer);

// Extract websocket handler from engine
const { websocket } = engine.handler();

// Export Bun server configuration
export default {
  port: process.env.PORT || 3000,
  // Bind all interfaces so the container accepts traffic from the Snapser gateway
  // (Bun's default hostname is not guaranteed across environments).
  hostname: "0.0.0.0",
  // Must be greater than the "pingInterval" option of the engine (default: 25 seconds)
  idleTimeout: 30,

  fetch(req: Request, server: any) {
    const url = new URL(req.url);

    // Always answer the readiness/liveness probe at the unprefixed /health. The platform
    // probes the container directly (no gateway prefix), so this must work even when
    // BASE_PATH moves the gateway-facing health route under the prefix.
    if (url.pathname === "/health") {
      return Response.json({ status: "ok", timestamp: Date.now() });
    }

    // Route Socket.IO requests to engine (path includes BASE_PATH when set)
    if (url.pathname.startsWith(`${BASE_PATH}/socket.io/`)) {
      return engine.handleRequest(req, server);
    }

    // Route all other requests to Hono
    return app.fetch(req, server);
  },

  websocket,
};

console.log(`🚀 Validator server starting on port ${process.env.PORT || 3000}`);
console.log(`📡 Socket.IO endpoint: /socket.io/`);
console.log(`🏥 Health check: /health`);
console.log(`🔧 MCP endpoint: /mcp`);