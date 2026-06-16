/**
 * Remote Config helper for the story catalog. The Remote Config snap has no
 * write API (app-config is published via the Snapser console's App Config
 * tool), so "uploading" is: emit the exact payload, paste it into the console
 * under version "v1", then verify the live config byte-matches the committed
 * catalog.
 *
 *   bun run tools/story-appconfig.ts emit     # the JSON to paste (pipe to pbcopy)
 *   bun run tools/story-appconfig.ts verify   # anon-login + GET + deep compare
 *
 * The catalog rides under the "story_catalog" key so later features can add
 * their own keys to the same app-config document.
 */

import catalog from "../../../content/story_catalog.json" with { type: "json" };

const GATEWAY = process.env.SNAPSER_GATEWAY_URL || "https://gateway.snapser.com/c4n1awfs";
const APP_CONFIG_VERSION = "v1";

/** Key-order-insensitive equality — the gateway echoes config back with
 *  alphabetized keys, so raw stringify comparison false-negatives. */
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

const cmd = process.argv[2] ?? "emit";

if (cmd === "emit") {
  console.log(JSON.stringify({ story_catalog: catalog }, null, 2));
} else if (cmd === "verify") {
  // Anonymous session (auth-passthrough is a no-op on this gateway — every
  // route needs a token). Reuses a fixed checker identity.
  const login = await fetch(`${GATEWAY}/v1/auth/login/anon`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: "story-catalog-verify", create_user: true }),
  });
  if (!login.ok) {
    console.error(`anon login failed: HTTP ${login.status} ${await login.text()}`);
    process.exit(1);
  }
  const { user } = (await login.json()) as { user: { id: string; session_token: string } };

  const res = await fetch(`${GATEWAY}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`, {
    headers: { "Token": user.session_token, "User-Id": user.id },
  });
  if (!res.ok) {
    console.error(`GET app-config/${APP_CONFIG_VERSION} failed: HTTP ${res.status} ${await res.text()}`);
    console.error("(Is the remote-config snap provisioned and the app config published?)");
    process.exit(1);
  }
  const body = (await res.json()) as { config?: { story_catalog?: unknown } };
  const live = body.config?.story_catalog;
  if (!live) {
    console.error("app-config has no story_catalog key — paste the `emit` output into the console App Config tool");
    process.exit(1);
  }
  if (!deepEqual(live, catalog)) {
    console.error("LIVE story_catalog DIFFERS from the committed validator/content/story_catalog.json — re-publish it");
    process.exit(1);
  }
  console.log(`✓ live app-config/${APP_CONFIG_VERSION} story_catalog matches the committed catalog (version ${(catalog as { catalog_version: number }).catalog_version})`);
} else if (cmd === "status") {
  // Report catalog_version across all three surfaces so drift is visible at a
  // glance: the committed file, the live Remote Config app-config, and the
  // deployed validator's loaded catalog (GET /api/status). Read-only; no secrets.
  const committedVersion = (catalog as { catalog_version: number }).catalog_version;
  console.log(`committed (validator/content/story_catalog.json): v${committedVersion}`);

  // Live Remote Config (anon session, like verify).
  let liveVersion: number | string = "unavailable";
  let liveMatches: boolean | string = "?";
  try {
    const login = await fetch(`${GATEWAY}/v1/auth/login/anon`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "story-catalog-status", create_user: true }),
    });
    if (login.ok) {
      const { user } = (await login.json()) as { user: { id: string; session_token: string } };
      const res = await fetch(`${GATEWAY}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`, {
        headers: { Token: user.session_token, "User-Id": user.id },
      });
      if (res.ok) {
        const body = (await res.json()) as { config?: { story_catalog?: { catalog_version?: number } } };
        const live = body.config?.story_catalog;
        liveVersion = live?.catalog_version ?? "absent";
        liveMatches = live ? deepEqual(live, catalog) : "absent";
      }
    }
  } catch (e) {
    liveVersion = `error: ${e}`;
  }
  console.log(`live Remote Config app-config/${APP_CONFIG_VERSION}: v${liveVersion} (matches committed: ${liveMatches})`);

  // Deployed validator's loaded catalog (no auth on /api/status).
  const base = process.env.VALIDATOR_STATUS_URL || `${GATEWAY}/v1/byosnap-validator`;
  let deployedVersion: number | string = "unavailable";
  try {
    const res = await fetch(`${base}/api/status`);
    if (res.ok) {
      const body = (await res.json()) as { story_catalog_version?: number; story_catalog_source?: string };
      deployedVersion = body.story_catalog_version ?? "unknown";
      console.log(`deployed validator (${base}/api/status): v${deployedVersion} (source ${body.story_catalog_source ?? "?"})`);
    } else {
      console.log(`deployed validator (${base}/api/status): HTTP ${res.status}`);
    }
  } catch (e) {
    console.log(`deployed validator (${base}/api/status): error: ${e}`);
  }
} else {
  console.error(`unknown command '${cmd}' — use emit | verify | status`);
  process.exit(1);
}
