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

function deepEqual(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
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
} else {
  console.error(`unknown command '${cmd}' — use emit | verify`);
  process.exit(1);
}
