#!/usr/bin/env bun
/**
 * artgen MCP shim — zero-dependency Bun stdio server registered in .mcp.json.
 *
 * Stateless proxy: every tool call becomes one HTTP request to the ArtGen
 * bridge inside the Godot editor (game/addons/artgen/bridge.gd, 127.0.0.1:4848,
 * env ARTGEN_BRIDGE_PORT). The editor owns the Recraft API key, the ledger and
 * the save pipeline; this process never sees the key. When the editor is
 * closed the bridge port is closed too, and every tool returns a clear
 * "editor offline" error instead of hanging.
 */

const PORT = Number(process.env.ARTGEN_BRIDGE_PORT ?? 4848);
const BASE = `http://127.0.0.1:${PORT}`;
// Generations run 10–60 s and the bridge holds the connection open.
const FETCH_TIMEOUT_MS = 180_000;

const EDITOR_OFFLINE =
  `ArtGen bridge unreachable on ${BASE} — editor offline. ` +
  `Open game/ in Godot 4.6 with the ArtGen plugin enabled, then retry.`;

type Json = Record<string, unknown>;

const TOOLS = [
  {
    name: "artgen_status",
    description:
      "ArtGen service status: balance, presets, save categories, config pins, history count.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "artgen_generate",
    description:
      "Generate images via Recraft in the occult-arcade style. Returns ledger records " +
      "with abs_path for each image so they can be read straight off disk. " +
      "Presets: icon-flat (SVG, default custom style, bg stripped on save), icon-raster " +
      "(PNG + removeBackground on save), card-glyph, card-illustrated, texture. " +
      "All presets default to Recraft v3; pass model 'vector_v41'/'raster_v41' for " +
      "Recraft v4.1 (custom styles + negative_prompt are v3-only and dropped on v4.x).",
    inputSchema: {
      type: "object",
      properties: {
        preset: { type: "string", description: "preset name (see artgen_status)" },
        subject: { type: "string", description: "what to draw, e.g. 'leaderboard trophy'" },
        n: { type: "integer", minimum: 1, maximum: 6, description: "variations (default 1)" },
        prompt: { type: "string", description: "full prompt override (optional)" },
        style_id: { type: "string", description: "style_id override or 'none' (optional)" },
        model: {
          type: "string",
          description:
            "model kind from config.json models map: 'vector' | 'raster' (Recraft v3, " +
            "supports custom styles) | 'vector_v41' | 'raster_v41' (Recraft v4.1 — " +
            "explicit style_id refused, preset styles dropped); raw Recraft model ids " +
            "also accepted (optional)",
        },
        size: {
          type: "string",
          description:
            "WxH override, e.g. 1024x1024 (optional; v4.x VECTOR models use " +
            "aspect-ratio sizes, so a WxH value is omitted and the API auto-selects)",
        },
        parent_id: { type: "string", description: "lineage parent generation id (optional)" },
      },
      required: ["preset", "subject"],
      additionalProperties: false,
    },
  },
  {
    name: "artgen_history",
    description: "Browse the committed generation ledger (newest first).",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "max records (default 50)" },
        preset: { type: "string", description: "filter by preset" },
        state: {
          type: "string",
          enum: ["generated", "saved", "discarded", "error"],
          description: "filter by state",
        },
        search: { type: "string", description: "substring match on subject/prompt/id" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "artgen_get",
    description: "Full record for one generation, including its lineage chain and abs_path.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "generation id (g_…)" } },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "artgen_save",
    description:
      "Promote a generation into the game: applies its post steps (bg strip / removeBackground), " +
      "copies to res://assets/generated/<category>/<name>.<ext>, imports it, and records AI " +
      "attribution in ai_manifest.json.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "generation id (g_…)" },
        category: { type: "string", enum: ["icons", "cards", "textures", "misc"] },
        name: { type: "string", description: "asset filename without extension" },
      },
      required: ["id", "category", "name"],
      additionalProperties: false,
    },
  },
  {
    name: "artgen_discard",
    description:
      "Mark a generation discarded in the ledger (file stays on disk; history is append-only).",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "generation id (g_…)" } },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "artgen_style_create",
    description:
      "Create a Recraft custom style from reference images (≤5 files, ≤5 MB total, ~40 credits). " +
      "Pass absolute paths; pin the returned style_id in config/presets to use it.",
    inputSchema: {
      type: "object",
      properties: {
        refs: {
          type: "array",
          items: { type: "string" },
          description: "absolute paths to PNG/JPG/WEBP reference images",
        },
        style: {
          type: "string",
          enum: ["any", "realistic_image", "digital_illustration", "vector_illustration", "icon"],
          description: "base style (default vector_illustration)",
        },
      },
      required: ["refs"],
      additionalProperties: false,
    },
  },
];

async function bridge(method: string, path: string, body?: Json): Promise<Json> {
  let res: Response;
  try {
    res = await fetch(BASE + path, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch {
    throw new Error(EDITOR_OFFLINE);
  }
  const data = (await res.json().catch(() => ({}))) as Json;
  if (!res.ok && data.error === undefined) {
    throw new Error(`bridge returned HTTP ${res.status}`);
  }
  return data;
}

function query(params: Record<string, unknown>): string {
  const pairs = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== null && v !== "")
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
  return pairs.length ? "?" + pairs.join("&") : "";
}

async function callTool(name: string, args: Json): Promise<Json> {
  switch (name) {
    case "artgen_status":
      return bridge("GET", "/status");
    case "artgen_generate":
      return bridge("POST", "/generate", args);
    case "artgen_history":
      return bridge("GET", "/history" + query(args));
    case "artgen_get":
      return bridge("GET", "/get" + query({ id: args.id }));
    case "artgen_save":
      return bridge("POST", "/save", args);
    case "artgen_discard":
      return bridge("POST", "/discard", args);
    case "artgen_style_create":
      return bridge("POST", "/style/create", args);
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

function reply(id: unknown, result: Json): void {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function replyError(id: unknown, code: number, message: string): void {
  process.stdout.write(
    JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n",
  );
}

async function handle(msg: Json): Promise<void> {
  const { id, method, params } = msg as { id?: unknown; method: string; params?: Json };
  switch (method) {
    case "initialize":
      reply(id, {
        protocolVersion: (params?.protocolVersion as string) ?? "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "artgen", version: "0.1.0" },
      });
      break;
    case "notifications/initialized":
    case "notifications/cancelled":
      break; // notifications get no response
    case "ping":
      reply(id, {});
      break;
    case "tools/list":
      reply(id, { tools: TOOLS });
      break;
    case "tools/call": {
      const name = (params?.name as string) ?? "";
      const args = (params?.arguments as Json) ?? {};
      try {
        const result = await callTool(name, args);
        const isError = result.ok === false;
        reply(id, {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          isError,
        });
      } catch (err) {
        reply(id, {
          content: [{ type: "text", text: (err as Error).message }],
          isError: true,
        });
      }
      break;
    }
    default:
      if (id !== undefined) replyError(id, -32601, `method not found: ${method}`);
  }
}

let buffer = "";
let pending = 0;
let stdinClosed = false;

function maybeExit(): void {
  if (stdinClosed && pending === 0) process.exit(0);
}

process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk: string) => {
  buffer += chunk;
  let newline: number;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line) as Json;
      pending += 1;
      void handle(msg).finally(() => {
        pending -= 1;
        maybeExit();
      });
    } catch {
      replyError(null, -32700, "parse error");
    }
  }
});
// don't drop in-flight tool calls (generations run 10–60 s) when stdin closes
process.stdin.on("end", () => {
  stdinClosed = true;
  maybeExit();
});
