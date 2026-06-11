import { Hono } from "hono";
import { cors } from "hono/cors";
import { InMemoryMatchStateStore } from "./store/match-state";
import { FileSystemHistoryStore } from "./store/history-store";
import { createMatchRoutes } from "./routes/match";
import { createValidatorMCP } from "./mcp";
import { getConfig } from "./config";
import { InventoryClient, resolveInventoryTransport } from "./snaps/inventory";
import { ValidatorService } from "./service";
import { startGrpcServer } from "./grpc";
import { HermesDispatcher, upgradeCallerHeaders } from "./hermes-ws";
import type { CallerHeaders } from "./service";

const store = new InMemoryMatchStateStore();
const historyStore = new FileSystemHistoryStore();
const config = getConfig();
const inventory = new InventoryClient(resolveInventoryTransport(config));
console.log(`💰 Currency awards: ${inventory.enabled ? `enabled (${inventory.transportKind})` : "disabled (no s2s credentials)"}`);

const service = new ValidatorService(store, inventory);
const dispatcher = new HermesDispatcher(service);

// gRPC is the production transport: Snapser Hermes proxies snap-api requests
// to this port inside the snapend (declared as the profile's internal "grpc"
// port). HTTP (below) keeps the probe, MCP debug surface, and history tooling.
await startGrpcServer(service, config.grpcPort);

// The Snapser gateway forwards the full route prefix (e.g. /v1/byosnap-validator)
// to the container without stripping it. Serve all routes under this base path
// so they match. Empty for local dev (no prefix).
const BASE_PATH = (process.env.BYOSNAP_BASE_PATH || "").replace(/\/+$/, "");

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
    version: "0.2.2",
    uptime: process.uptime(),
    transport: "grpc+hermes",
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
      hermesWs: "/hermes/ws?token=<player-or-session>",
      grpc: `:${config.grpcPort} (moveborne.validator.v1.ValidatorService)`,
      history: "/api/match/{init-from-history,save-history,load-history/:id}",
      mcp: "/mcp",
    },
  });
});

const matchRoutes = createMatchRoutes(store, historyStore);
app.route("/api/match", matchRoutes);

const mcpServer = createValidatorMCP(store);
app.route("/mcp", mcpServer);

const HERMES_WS_PATHS = new Set([`${BASE_PATH}/hermes/ws`, "/hermes/ws"]);

interface WsData {
  caller: CallerHeaders;
}

// Export Bun server configuration
export default {
  port: config.port,
  // Bind all interfaces so the container accepts traffic from the Snapser gateway
  // (Bun's default hostname is not guaranteed across environments).
  hostname: "0.0.0.0",
  idleTimeout: 30,

  fetch(req: Request, server: any) {
    const url = new URL(req.url);

    // Always answer the readiness/liveness probe at the unprefixed /health. The platform
    // probes the container directly (no gateway prefix), so this must work even when
    // BASE_PATH moves the gateway-facing health route under the prefix.
    if (url.pathname === "/health") {
      return Response.json({ status: "ok", timestamp: Date.now() });
    }

    // Hermes-envelope WebSocket (local-dev emulation of the gateway endpoint).
    if (HERMES_WS_PATHS.has(url.pathname)) {
      const caller = upgradeCallerHeaders(req.headers, url);
      if (!caller["user-id"]) {
        return Response.json(
          { error: "UNAUTHORIZED", message: "Missing token query param or gateway User-Id" },
          { status: 401 },
        );
      }
      const ok = server.upgrade(req, { data: { caller } satisfies WsData });
      if (ok) return undefined;
      return new Response("WebSocket upgrade failed", { status: 400 });
    }

    return app.fetch(req, server);
  },

  websocket: {
    async message(ws: any, raw: string | Uint8Array) {
      if (typeof raw === "string") {
        ws.close(1003, "binary protobuf frames only");
        return;
      }
      const response = await dispatcher.handleFrame(raw, (ws.data as WsData).caller);
      ws.sendBinary ? ws.sendBinary(response) : ws.send(response);
    },
  },
};

console.log(`🚀 Validator server starting on port ${config.port}`);
console.log(`📡 Hermes-envelope WS: /hermes/ws?token=<player-id> (local emulation)`);
console.log(`🏥 Health check: /health`);
console.log(`🔧 MCP endpoint: /mcp`);
