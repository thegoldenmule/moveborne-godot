/**
 * Generate the client's baked story catalog from the ONE canonical source.
 *
 *   bun run tools/sync-catalog.ts          # copy content/story_catalog.json -> game/story/story_catalog.json
 *   bun run tools/sync-catalog.ts check    # exit non-zero if they differ (CI / pre-commit guard)
 *
 * validator/content/story_catalog.json is the single hand-edited catalog. The
 * Godot client needs an on-disk res:// copy, so we GENERATE it here (byte-for-
 * byte) instead of hand-maintaining two files; verify_story_catalog.gd byte-
 * compares them as the drift guard.
 */

const SRC = new URL("../../../content/story_catalog.json", import.meta.url);
const DST = new URL("../../../../game/story/story_catalog.json", import.meta.url);

const cmd = process.argv[2] ?? "copy";
const src = new Uint8Array(await Bun.file(SRC).arrayBuffer());

if (cmd === "check") {
  const dst = new Uint8Array(await Bun.file(DST).arrayBuffer().catch(() => new ArrayBuffer(0)));
  const same = src.length === dst.length && src.every((b, i) => b === dst[i]);
  if (!same) {
    console.error("DRIFT: game/story/story_catalog.json differs from validator/content/story_catalog.json — run `bun run sync:catalog`");
    process.exit(1);
  }
  console.log("✓ baked client catalog matches the canonical source");
} else if (cmd === "copy") {
  await Bun.write(DST, src);
  console.log(`synced story catalog -> game/story/story_catalog.json (${src.length} bytes)`);
} else {
  console.error(`unknown command '${cmd}' — use copy | check`);
  process.exit(1);
}
