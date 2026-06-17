/**
 * Remote Config helper for the Daily Missions block. The Remote Config snap has
 * no write API (app-config is published via the Snapser console's App Config
 * tool), so "uploading" is: emit the exact payload, paste it into the console
 * under version "v1" ALONGSIDE the story_catalog key (the app-config document
 * carries both — merge, don't overwrite), then verify the live config matches.
 *
 *   bun run tools/daily-missions-appconfig.ts emit     # the JSON to paste (pipe to pbcopy)
 *   bun run tools/daily-missions-appconfig.ts verify   # anon-login + GET + deep compare
 *   bun run tools/daily-missions-appconfig.ts status    # version drift across surfaces
 *
 * The block rides under the "daily_missions" key, a sibling of "story_catalog";
 * see validator/src/validator/tools/story-appconfig.ts for the catalog twin.
 */

import block from "../../../content/daily_missions.json" with { type: "json" };

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

const cmd = process.argv[2] ?? "emit";

if (cmd === "emit") {
  console.log(JSON.stringify({ daily_missions: block }, null, 2));
} else if (cmd === "verify") {
  const user = await anonSession("daily-missions-verify");
  if (!user) {
    console.error("anon login failed");
    process.exit(1);
  }
  const res = await fetch(`${GATEWAY}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`, {
    headers: { Token: user.session_token, "User-Id": user.id },
  });
  if (!res.ok) {
    console.error(`GET app-config/${APP_CONFIG_VERSION} failed: HTTP ${res.status} ${await res.text()}`);
    console.error("(Is the remote-config snap provisioned and the app config published?)");
    process.exit(1);
  }
  const body = (await res.json()) as { config?: { daily_missions?: unknown } };
  const live = body.config?.daily_missions;
  if (!live) {
    console.error("app-config has no daily_missions key — paste the `emit` output into the console App Config tool (alongside story_catalog)");
    process.exit(1);
  }
  if (!deepEqual(live, block)) {
    console.error("LIVE daily_missions DIFFERS from the committed validator/content/daily_missions.json — re-publish it");
    process.exit(1);
  }
  console.log(`✓ live app-config/${APP_CONFIG_VERSION} daily_missions matches the committed block (version ${(block as { version: number }).version})`);
} else if (cmd === "status") {
  const committedVersion = (block as { version: number }).version;
  console.log(`committed (validator/content/daily_missions.json): v${committedVersion}`);

  let liveVersion: number | string = "unavailable";
  let liveMatches: boolean | string = "?";
  try {
    const user = await anonSession("daily-missions-status");
    if (user) {
      const res = await fetch(`${GATEWAY}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`, {
        headers: { Token: user.session_token, "User-Id": user.id },
      });
      if (res.ok) {
        const body = (await res.json()) as { config?: { daily_missions?: { version?: number } } };
        const live = body.config?.daily_missions;
        liveVersion = live?.version ?? "absent";
        liveMatches = live ? deepEqual(live, block) : "absent";
      }
    }
  } catch (e) {
    liveVersion = `error: ${e}`;
  }
  console.log(`live Remote Config app-config/${APP_CONFIG_VERSION}: v${liveVersion} (matches committed: ${liveMatches})`);
} else {
  console.error(`unknown command '${cmd}' — use emit | verify | status`);
  process.exit(1);
}
