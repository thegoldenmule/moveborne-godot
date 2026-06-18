/**
 * Generic Remote Config app-config driver — the ONE tool that emits, verifies,
 * and reports the whole Snapser app-config document. It replaces the per-feature
 * twins (story-appconfig.ts, daily-missions-appconfig.ts), which differed only in
 * three data values now captured by the manifest.
 *
 *   bun run tools/appconfig.ts emit                 # the FULL {key: content,...} document (pipe to pbcopy)
 *   bun run tools/appconfig.ts verify [key]         # anon-login + GET + per-key deep compare
 *   bun run tools/appconfig.ts verify --json        # same, machine-readable (the Godot RC tool parses this)
 *   bun run tools/appconfig.ts status [key]         # committed-vs-live version table
 *
 * Remote Config has NO write API: "publishing" is a manual console paste of `emit`'s
 * output into the App Config tool under the manifest's app_config_version, then
 * `verify` to confirm the live document byte-matches the committed blobs.
 *
 * Registry: validator/content/app_config.manifest.json — { app_config_version,
 * entries:[{key,file,version_field,label}] }. Adding a feature is a one-line append
 * here; no new tool. The Godot Remote Config editor reads the SAME manifest, so the
 * editor table, the built payload, and this verify can never disagree on the key set.
 *
 * Exit codes: 0 = all checked entries match · 1 = drift / absent · 2 = login / HTTP
 * / manifest / content-file error. `emit` FAILS LOUD (exit 2) on any missing or
 * unparseable content file — it never prints a partial document (a partial paste
 * would silently drop a sibling key).
 */

const GATEWAY = process.env.SNAPSER_GATEWAY_URL || "https://gateway.snapser.com/c4n1awfs";

type ManifestEntry = { key: string; file: string; version_field: string; label: string };
type Manifest = { app_config_version: string; entries: ManifestEntry[] };

/** Key-order-insensitive equality — the gateway echoes config back with
 *  alphabetized keys, so raw stringify comparison false-negatives. Defined ONCE. */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v !== null && typeof v === "object") {
    const entries = Object.entries(v as Record<string, unknown>)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([k, val]) => `${JSON.stringify(k)}:${canonical(val)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(v);
}

function deepEqual(a: unknown, b: unknown): boolean {
  return canonical(a) === canonical(b);
}

async function loadManifest(): Promise<Manifest> {
  const url = new URL("../../../content/app_config.manifest.json", import.meta.url);
  if (!(await Bun.file(url).exists())) {
    console.error("manifest not found: validator/content/app_config.manifest.json");
    process.exit(2);
  }
  const m = (await Bun.file(url).json()) as Manifest;
  if (!m || typeof m.app_config_version !== "string" || !Array.isArray(m.entries)) {
    console.error("manifest malformed: expected { app_config_version, entries:[...] }");
    process.exit(2);
  }
  for (const e of m.entries) {
    if (!e.key || !e.file || !e.version_field) {
      console.error(`manifest entry missing key/file/version_field: ${JSON.stringify(e)}`);
      process.exit(2);
    }
  }
  return m;
}

/** Read one entry's committed content. Fails loud (exit 2) when the file is
 *  missing or unparseable — never returns a partial result. */
async function loadEntry(e: ManifestEntry): Promise<Record<string, unknown>> {
  const url = new URL(`../../../content/${e.file}`, import.meta.url);
  if (!(await Bun.file(url).exists())) {
    console.error(`content file not found for key "${e.key}": validator/content/${e.file}`);
    process.exit(2);
  }
  try {
    return (await Bun.file(url).json()) as Record<string, unknown>;
  } catch (err) {
    console.error(`content file for key "${e.key}" is not valid JSON (validator/content/${e.file}): ${err}`);
    process.exit(2);
  }
}

/** The exact document to publish: { key: content } for EVERY entry, merged. */
async function emitDocument(m: Manifest): Promise<Record<string, unknown>> {
  const doc: Record<string, unknown> = {};
  for (const e of m.entries) doc[e.key] = await loadEntry(e);
  return doc;
}

/** Explicit version read — never coerce a missing field to 0 (a fresh block can
 *  legitimately start at version 0). undefined means "field absent". */
function versionOf(content: Record<string, unknown>, e: ManifestEntry): number | undefined {
  const v = content[e.version_field];
  return typeof v === "number" ? v : undefined;
}

async function anonSession(username: string): Promise<{ id: string; session_token: string } | null> {
  const login = await fetch(`${GATEWAY}/v1/auth/login/anon`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, create_user: true }),
  });
  if (!login.ok) return null;
  const { user } = (await login.json()) as { user: { id: string; session_token: string } };
  return user;
}

/** GET the live app-config.config object (or null on login/HTTP failure). */
async function fetchLiveConfig(m: Manifest, username: string): Promise<Record<string, unknown> | null> {
  const user = await anonSession(username);
  if (!user) return null;
  const res = await fetch(`${GATEWAY}/v1/remote-config/app-config/${m.app_config_version}`, {
    headers: { Token: user.session_token, "User-Id": user.id },
  });
  if (!res.ok) return null;
  const body = (await res.json()) as { config?: Record<string, unknown> };
  return body.config ?? {};
}

type EntryResult = {
  key: string;
  status: "match" | "drift" | "absent";
  committed_version: number | undefined;
  live_version: number | undefined;
};

function compareEntry(
  e: ManifestEntry,
  committed: Record<string, unknown>,
  live: Record<string, unknown>,
): EntryResult {
  const committed_version = versionOf(committed, e);
  if (!(e.key in live)) {
    return { key: e.key, status: "absent", committed_version, live_version: undefined };
  }
  const liveBlock = live[e.key] as Record<string, unknown>;
  const live_version = versionOf(liveBlock, e);
  const status = deepEqual(liveBlock, committed) ? "match" : "drift";
  return { key: e.key, status, committed_version, live_version };
}

// ── CLI ──────────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const cmd = argv[0] ?? "emit";
const asJson = argv.includes("--json");
const selectedKey = argv.slice(1).find((a) => !a.startsWith("--"));

const manifest = await loadManifest();
const entries = selectedKey
  ? manifest.entries.filter((e) => e.key === selectedKey)
  : manifest.entries;

if (selectedKey && entries.length === 0) {
  console.error(`unknown key "${selectedKey}" — manifest keys: ${manifest.entries.map((e) => e.key).join(", ")}`);
  process.exit(2);
}

if (cmd === "emit") {
  // stdout = ONLY the JSON document (pipeable to pbcopy); diagnostics go to stderr.
  console.log(JSON.stringify(await emitDocument(manifest), null, 2));
} else if (cmd === "verify") {
  const live = await fetchLiveConfig(manifest, "appconfig-verify");
  if (!live) {
    if (asJson) console.log(JSON.stringify({ ok: false, error: "login_or_http_failed", results: [] }));
    else {
      console.error("anon login / GET app-config failed");
      console.error("(Is the remote-config snap provisioned and the app config published?)");
    }
    process.exit(2);
  }
  const results: EntryResult[] = [];
  for (const e of entries) results.push(compareEntry(e, await loadEntry(e), live));
  const allMatch = results.every((r) => r.status === "match");
  if (asJson) {
    console.log(JSON.stringify({ ok: allMatch, app_config_version: manifest.app_config_version, results }));
  } else {
    for (const r of results) {
      if (r.status === "match") console.log(`✓ ${r.key} matches (v${r.committed_version ?? "?"})`);
      else if (r.status === "absent") console.error(`✗ ${r.key} ABSENT from live app-config/${manifest.app_config_version}`);
      else console.error(`✗ ${r.key} DRIFT (live v${r.live_version ?? "?"} / committed v${r.committed_version ?? "?"})`);
    }
    if (allMatch) console.log(`✓ live app-config/${manifest.app_config_version} matches committed (${results.length} key(s))`);
    else console.error("re-publish: paste `bun run appconfig:emit` output into the Snapser console App Config tool");
  }
  process.exit(allMatch ? 0 : 1);
} else if (cmd === "status") {
  const live = await fetchLiveConfig(manifest, "appconfig-status");
  const rows: EntryResult[] = [];
  for (const e of entries) {
    const committed = await loadEntry(e);
    if (!live) {
      rows.push({ key: e.key, status: "absent", committed_version: versionOf(committed, e), live_version: undefined });
    } else {
      rows.push(compareEntry(e, committed, live));
    }
  }
  if (asJson) {
    console.log(JSON.stringify({ app_config_version: manifest.app_config_version, live: live !== null, results: rows }));
  } else {
    console.log(`app-config/${manifest.app_config_version}${live ? "" : "  (live: unavailable)"}`);
    for (const r of rows) {
      const c = r.committed_version ?? "absent";
      const l = live ? (r.live_version ?? (r.status === "absent" ? "absent" : "?")) : "?";
      console.log(`  ${r.key}: committed v${c} | live v${l} | ${live ? r.status : "unknown"}`);
    }
  }
  // status is read-only and never fails on drift.
} else {
  console.error(`unknown command "${cmd}" — use emit | verify [key] [--json] | status [key]`);
  process.exit(2);
}
