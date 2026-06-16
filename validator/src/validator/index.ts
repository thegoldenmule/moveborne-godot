import { Hono } from "hono";
import { cors } from "hono/cors";
import { InMemoryMatchStateStore } from "./store/match-state";
import { FileSystemHistoryStore } from "./store/history-store";
import { createMatchRoutes } from "./routes/match";
import { createValidatorMCP } from "./mcp";
import { getConfig } from "./config";
import { InventoryClient, resolveInventoryTransport } from "./snaps/inventory";
import { StorageClient, resolveStorageTransport } from "./snaps/storage";
import { RemoteConfigClient, resolveRemoteConfigTransport } from "./snaps/remote-config";
import { loadCatalog, refreshCatalog, loadedInfo, release } from "./story/catalog";
import { ValidatorService } from "./service";
import { startGrpcServer } from "./grpc";
import { HermesDispatcher, upgradeCallerHeaders } from "./hermes-ws";
import type { CallerHeaders } from "./service";
import pkg from "./package.json" with { type: "json" };

const config = getConfig();
// Release a match's pinned catalog version when it leaves the store (expiry or
// delete), so old versions drain from the registry once no match needs them.
const store = new InMemoryMatchStateStore((m) => {
  if (m.catalog_version !== undefined) release(m.catalog_version);
});
const historyStore = new FileSystemHistoryStore();
const inventory = new InventoryClient(resolveInventoryTransport(config));
console.log(`💰 Currency awards: ${inventory.enabled ? `enabled (${inventory.transportKind})` : "disabled (no s2s credentials)"}`);

const storage = new StorageClient(resolveStorageTransport(config));
console.log(`⭐ Story progress: ${storage.enabled ? `enabled (${storage.transportKind})` : "disabled (no s2s credentials)"}`);

// The story catalog is the validator's RUNTIME source: pulled from Remote Config
// (s2s), with the committed file as the dev/test fallback. In production we do
// NOT block boot — non-story matches serve while the catalog loads in the
// background (story init/grade return UNAVAILABLE until it lands). In dev (no
// remote-config s2s) we load the committed file now so a malformed edit fails
// fast at boot, not as NaN grades.
const remoteConfig = new RemoteConfigClient(resolveRemoteConfigTransport(config));
console.log(`📖 Story catalog: ${remoteConfig.enabled ? `Remote Config (${remoteConfig.transportKind})` : "committed fallback (no remote-config s2s)"}`);
if (remoteConfig.enabled) {
  loadCatalog(remoteConfig).catch((e) => console.error("story catalog initial load failed:", e));
} else {
  await loadCatalog(remoteConfig, 1);
}

const service = new ValidatorService(store, inventory, storage);
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
  const cat = loadedInfo();
  return c.json({
    server: "validator",
    version: pkg.version,
    uptime: process.uptime(),
    transport: "grpc+hermes",
    // Which s2s transport the currency-award path resolved to (no secrets).
    awards: inventory.enabled ? inventory.transportKind : "disabled",
    // The catalog version this validator is currently serving (0 until loaded);
    // the status tool compares it across surfaces. No secrets.
    story_catalog_version: cat.version,
    story_catalog_source: remoteConfig.enabled ? remoteConfig.transportKind : "committed-fallback",
    story_catalog_loaded_at: cat.loadedAt,
  });
});

// Force a catalog re-fetch from Remote Config (ops + the editor status panel).
// Internal-guarded when an internal header is configured; open in local dev.
app.post("/api/story/catalog/refresh", async (c) => {
  if (config.internalHeader && c.req.header("Gateway") !== config.internalHeader) {
    return c.json({ error: "forbidden" }, 403);
  }
  const result = await refreshCatalog();
  return c.json(result);
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
