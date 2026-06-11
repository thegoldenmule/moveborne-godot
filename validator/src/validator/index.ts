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
import pkg from "./package.json" with { type: "json" };

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
    version: pkg.version,
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

// The Hermes-emulation WebSocket exists ONLY for local dev: it stands in for the
// Snapser Hermes service so the game has one client codepath. Deployed, the game
// reaches the gRPC service through the real gateway Hermes (which stamps the
// gateway-validated identity as gRPC metadata) — the BYOSnap never serves this
// route in the snapend. We therefore mount it only when there is NO gateway
// prefix (local dev), so the token→self-stamped-identity trust (correct only
// when nothing but the local process can reach the port) cannot exist in
// deployed code at all. (BASE_PATH is set in every deployed template.)
const HERMES_WS_LOCAL_ONLY = BASE_PATH === "";

interface WsData {
  caller: CallerHeaders;
}

// Export Bun server configuration
export default {
  port: config.port,
  // Bind all interfaces so the container accepts traffic from the Snapser gateway
  // (Bun's default hostname is not guaranteed across environments).
  hostname: "0.0.0.0",
  // The Hermes envelope has no client-initiated keepalive (the live gateway drops
  // the connection on client pings), so an idle local-emulation socket relies on
  // this timeout window. Use Bun's max so paused local matches don't drop mid-play;
  // the DEPLOYED path's keepalive is the managed Hermes service's responsibility.
  idleTimeout: 255,

  fetch(req: Request, server: any) {
    const url = new URL(req.url);

    // Always answer the readiness/liveness probe at the unprefixed /health. The platform
    // probes the container directly (no gateway prefix), so this must work even when
    // BASE_PATH moves the gateway-facing health route under the prefix.
    if (url.pathname === "/health") {
      return Response.json({ status: "ok", timestamp: Date.now() });
    }

    // Hermes-envelope WebSocket (local-dev emulation of the gateway endpoint).
    if (HERMES_WS_LOCAL_ONLY && url.pathname === "/hermes/ws") {
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
