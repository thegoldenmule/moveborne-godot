# Remote Config & Content Authoring

**Status:** current

## Kind
subsystem

## Summary
**BUILT** (commit `cccc4bd`; all headless verifiers pass, validator type-check clean, live `appconfig status` confirmed). The editor-side pipeline that authors Moveborne's committed content and publishes it to Snapser Remote Config, separating content **production** from Remote Config **aggregation**. Built on the *Editor Tool Framework* (service + view; headless `ToolService`; `ContentStore`; `EditorToolUi`). Three tools, one registry, one CLI:

1. **Remote Config tool** (`addons/remote_config_editor/`): the single aggregation point. Reads the manifest, builds the *whole* `app-config/v1` document `{story_catalog, daily_missions, …}`, copies the full publish payload, and runs Check Sync.
2. **Daily Missions tool** (`addons/daily_missions_editor/`): authors `validator/content/daily_missions.json` (one target; no baked copy).
3. **Story Map refactor**: removed its Remote Config tab + the two RC service helpers; keeps Catalog / Map-dots authoring and the 3-file save that still emits the `story_catalog.json` blob.

Underneath: `validator/content/app_config.manifest.json` (the registry) + one generic `validator/src/validator/tools/appconfig.ts` (`emit | verify | status`, `--json`, per-key drift) that **replaced** the two near-identical per-feature `*-appconfig.ts` scripts (deleted). Adding the next block (`daily_login`) is a one-line manifest append, not an N-th copied script + tab.

## Purpose
Two real problems motivate the redesign. The Snapser app-config is **one JSON document** with sibling keys (`story_catalog`, `daily_missions`, soon `daily_login`), published by a **manual console paste** under version `v1` (Remote Config has no write API).

- **Partial-document footgun.** Each per-feature tool emits only its *own* key. `daily-missions-appconfig.ts`'s `emit` literally instructs the operator to *"paste ALONGSIDE the story_catalog key (the app-config document carries both — merge, don't overwrite)"* — so a one-key paste silently drops the others. **No single place knows the full document.**
- **Copy-paste duplication.** `story-appconfig.ts` and `daily-missions-appconfig.ts` are ~95% identical (same `canonical()` / `deepEqual()` / anon-login / `emit|verify|status`), differing only in three *data* values: the content file, the app-config key, and the version-field name (`catalog_version` vs `version`). Story Map's Remote Config tab hardcodes `story_catalog`, so it cannot aggregate anything else.

The fix is separation of concerns: each content tool writes **only** its own `validator/content/<key>.json` blob; one dedicated Remote Config tool reads a registry and aggregates the **whole** document, so the published payload is complete *by construction*. The delta between the per-feature scripts is pure data, so it moves into a manifest — not a third copy of the code.

## Design notes
Topology (resolved). An adversarial design pass found that the obvious sketches were partly ALTERNATIVES, not one plan: one variant kept Remote Config logic inside StoryMapService and rewrote it to read the manifest, while another deleted it and moved everything to a new dedicated tool. The chosen topology is the dedicated tool: a new addons/remote_config_editor tool is the ONLY place that aggregates and publishes the app-config document; Remote Config is REMOVED from Story Map (not rewritten in place). Each per-feature content tool (Story Map, Daily Missions, future Daily Login) writes only its own validator/content/<key>.json blob and knows nothing about Remote Config. This separation-of-concerns is what the rest of this node assumes.

Remote Config tool — RemoteConfigService (a ToolService; headless, no Control/EditorInterface refs). It loads validator/content/app_config.manifest.json plus every entry's blob, and exposes: build_document() — THE single pure aggregation point: reads only manifest+blobs, no IO/clipboard/exec, returns {key: blob} in manifest order, so the headless verifier asserts the exact published shape; versions() — per-key [{key,file,label,present,version}] driving the dock table; validate() — structural problems ([] == publishable): file missing, blob unparseable, version_field missing/non-int, duplicate key; copy_publish_payload() — gated on validate(); copies the WHOLE document via DisplayServer.clipboard_set; check_sync() — shells out to bun appconfig.ts verify --json and parses the per-key result (code -1 = bun missing, surfaced as a hint, exactly as StoryMapService did). The dock is a thin EditorToolUi view (key/file/version/present table + JSON preview pane + Copy/Check buttons + per-key drift readout + status label); no BridgeServer (publishing is a manual paste; nothing to drive over HTTP).

```gdscript
@tool
class_name RemoteConfigService
extends "res://addons/editor_tool_kit/tool_service.gd"

const ContentStore := preload("res://addons/editor_tool_kit/content_store.gd")
const MANIFEST_REL := "validator/content/app_config.manifest.json"

signal changed
var manifest: Dictionary = {}   # {app_config_version, entries:[...]}
var blobs: Dictionary = {}      # key -> parsed content (or {} when missing)

func reload() -> void:
    manifest = ContentStore.load_json(_repo_path(MANIFEST_REL))
    blobs.clear()
    for e in manifest.get("entries", []):
        blobs[str(e["key"])] = ContentStore.load_json(
            _repo_path("validator/content/".path_join(str(e["file"]))))
    clear_dirty(); changed.emit()

# THE single aggregation point — pure, headless-asserted.
func build_document() -> Dictionary:
    var doc := {}
    for e in manifest.get("entries", []):
        var b: Dictionary = blobs.get(str(e["key"]), {})
        if not b.is_empty():
            doc[str(e["key"])] = b   # missing blobs blocked by validate()
    return doc

func copy_publish_payload() -> Dictionary:
    var problems := validate()
    if not problems.is_empty():
        return err(str(problems))            # invalid -> do NOT touch the clipboard
    DisplayServer.clipboard_set(JSON.stringify(build_document(), "  "))
    return ok({"keys": build_document().keys()})

func check_sync() -> Dictionary:             # reuse the ONE TS comparator
    var out: Array = []
    var args := [_repo_path("validator/src/validator/tools/appconfig.ts"), "verify", "--json"]
    var code := OS.execute("bun", args, out, true)
    return {"ok": code == 0, "code": code, "out": out}   # out parsed per-key by the dock
```

Generic appconfig.ts (replaces story-appconfig.ts + daily-missions-appconfig.ts; KEEP sync-catalog.ts — it bakes catalog bytes into the Godot res:// tree, an unrelated drift guard). Commands: emit prints ONLY the merged {key: content} JSON to stdout (all diagnostics to stderr) for piping to pbcopy, and FAILS LOUD (exit 2) if any registered file is missing or unparseable — it never prints a partial document; verify [key?] anon-logs-in once, GETs app-config/{app_config_version}, deep-compares per key with the key-order-insensitive canonical() (the gateway alphabetizes keys), supports --json for the GDScript caller, exit 0 = all match, 1 = drift/absent, 2 = login/HTTP/manifest error; status prints a per-key committed-vs-live version table, read-only, never fails on drift. CRITICAL: use explicit presence checks — (e.key in live) for absent, typeof committed[version_field] === number for the version — never coerce a missing/zero version to 0 (a new daily_login block can legitimately start at version 0; the old !live / ?? absent truthiness would misreport it).

```typescript
// validator/src/validator/tools/appconfig.ts  (emit | verify | status)
type ManifestEntry = { key: string; file: string; version_field: string; label: string };
type Manifest = { app_config_version: string; entries: ManifestEntry[] };

const manifest: Manifest = await Bun.file(
  new URL("../../../content/app_config.manifest.json", import.meta.url)).json();

async function loadEntry(e: ManifestEntry) {
  const url = new URL(`../../../content/${e.file}`, import.meta.url);
  if (!(await Bun.file(url).exists())) { console.error(`missing ${e.file}`); process.exit(2); }
  return Bun.file(url).json();                 // dynamic read — path is per-row
}

// emit: print ONLY the full document; never a partial one.
const doc: Record<string, unknown> = {};
for (const e of manifest.entries) doc[e.key] = await loadEntry(e);

function present(live: Record<string, unknown>, e: ManifestEntry) { return e.key in live; }
function versionOf(c: Record<string, unknown>, e: ManifestEntry) {
  const v = c[e.version_field];
  return typeof v === "number" ? v : undefined;  // no missing -> 0 coercion
}
```

Daily Missions tool — DailyMissionsService (a ToolService) authoring the single file validator/content/daily_missions.json (one ContentStore target; no baked copy). Mirrors StoryMapService: in-memory block; mission CRUD (add/remove/rename); set_mission_field for title/icon/desc/reward; rotation editing (set_anchor; set/add/remove per weekday 0..6); set_enabled; validate() (anchor in catalog; every by_weekday id in catalog; every icon in the allowed set; reward non-empty; warnings for an empty weekday or an unused catalog entry); canonical serialize() with a stable key order (enabled, version, anchor, by_weekday with string keys 0..6, catalog) and int-coerced version; save() via ContentStore.save_all + bump_then on version gated on is_dirty(). rename_mission cascades into ALL three reference sites — the catalog key, every by_weekday array, and the anchor — exactly as StoryMapService.rename_level cascades dots. ICON_GLYPHS is hoisted from daily_missions_panel.gd up to MbDailyMissions (the headless model) so the runtime panel, the editor icon picker, and validate() all read one list. Dock: mission tree + edit form, anchor picker, a 7-day rotation grid (each weekday a multi-select chip set over the catalog ids, with the anchor pinned as a disabled lead chip), Save/Validate/Reload footer, and a copyable canonical-id readout for manual Quest provisioning. One-time cost: the first save reflows the hand-aligned daily_missions.json into plain 2-space JSON — land that whitespace-only reflow as its OWN commit so it does not pollute the feature diff.

Story Map refactor — a pure subtraction (grep-verified migration-safe). dock.gd: remove the _rc_status field, the _build_rc_tab(tabs) call + the whole _build_rc_tab func, _check_catalog_sync(), _copy_publish_payload(), and the Catalog-Remote-Config section banner; the TabContainer drops to two tabs (Catalog, Map dots); rewrite the post-save bumped hint (currently says publish via the Remote Config tab) to point at the new Remote Config tool. story_map_service.gd: remove check_catalog_sync() and copy_publish_payload(); KEEP CANONICAL_REL, save()/save_to(), the serializers, _repo_path(), and the validator/content/story_catalog.json write inside save_all — that is the catalog blob the Remote Config tool aggregates. Confirmed: those two helpers are referenced only in story_map_service.gd + dock.gd; verify_story_map_service.gd never touched them (it uses CANONICAL_REL + _repo_path, both retained), so it passes unchanged. Catalog/Map-dots authoring and the 3-file byte-identical save are untouched.

Migration — update these in LOCKSTEP with deleting the per-feature scripts (the adversarial pass found callers the sketches under-counted): StoryMapService needs no repoint (its shell-out is deleted with the RC helpers); update validator/README.md publish instructions (~line 128); update the BYOSnap deploy wiki page (Deploying the Validator) via the wiki MCP — its pre-flight gate runs bun ... story-appconfig.ts status to confirm live Remote Config matches the committed catalog before deploy, so that gate must be repointed to appconfig.ts status or the documented safety check silently can no longer run (and the wiki is read-only on disk — edit via mutatePage, never by hand). package.json has NO existing per-feature appconfig scripts (the tools were run by direct path), so ADD three fresh scripts appconfig:emit / appconfig:verify / appconfig:status = (cd src/validator && bun run tools/appconfig.ts <cmd>); keep emit's stdout strictly JSON. Add a verifier asserting app_config.manifest.json.app_config_version == MbRemoteConfigClient.APP_CONFIG_VERSION.

Open considerations. (1) Cost/benefit of the Daily Missions tool: daily_missions.json is ~1.5 KB / 7 entries, so a dedicated editor (rename-cascade, chip grid, ICON_GLYPHS hoist) may exceed the value vs. hand-editing — it can be deferred without blocking the manifest + Remote Config tool + Story Map refactor, which deliver the footgun fix on their own. (2) Quest/Trackable provisioning stays MANUAL (Snapser console, no write API): authoring a mission id with no backing server Quest is silently broken at runtime, and neither tool can verify backend existence — the canonical-id readout mitigates but does not replace an operator checklist. (3) The Remote Config tool reintroduces the bun-on-PATH dependency that leaving Story Map removes (OS.execute for Check sync) — the editor launched from Finder often lacks bun on PATH, so the code -1 path must show a clear hint, not a silent failure.

Dock layout (post-build UX fixes, commit 35c1d36). Two issues surfaced once the tools were used in the editor and were fixed: (1) the Remote Config dock now puts the keys table and the payload preview in a draggable VSplitContainer (was a fixed VBox stack) so either pane can be resized; (2) the Daily Missions dock scrolls its two-column content inside a ScrollContainer above a PINNED Save/Validate footer — previously a fixed ~520px no-scroll dock pushed the footer (and with it the editor's bottom-panel tab strip) off-screen, blocking access to the other tools. Both stay kit-standard: EditorToolUi builders, method-callable signal binds, headless-safe service.

## Components
_No components._

## Dependencies
- **depends-on** → [Editor Tool Framework](architecture:mqh31a29-0001-sy7uqn) — All three tools are built on the Editor Tool Framework bases (EditorToolPlugin / ToolService / ContentStore / EditorToolUi); the RC + Daily Missions services are headless ToolServices.
- **depends-on** → [Validator](architecture:mq1c2ixi-000h-kd018q) — The validator consumes the published app-config/v1 document at runtime (the catalog pull); this pipeline produces exactly what it reads, so the manifest's app_config_version + per-key shape must match the runtime contract.

## Code references
- file `NEW: the registry (app_config_version + entries[{key,file,version_field,label}]); read by both runtimes` in `validator/content/app_config.manifest.json`
- file `NEW: generic emit|verify|status (manifest-driven; replaces the two per-feature scripts)` in `validator/src/validator/tools/appconfig.ts`
- file `DELETE: subsumed by appconfig.ts` in `validator/src/validator/tools/story-appconfig.ts`
- file `DELETE: subsumed by appconfig.ts` in `validator/src/validator/tools/daily-missions-appconfig.ts`
- file `UNCHANGED: bakes catalog bytes into the res:// tree (orthogonal drift guard)` in `validator/src/validator/tools/sync-catalog.ts`
- class `NEW: RemoteConfigService (build_document = the single aggregation point)` in `game/addons/remote_config_editor/remote_config_service.gd`
- file `NEW: Remote Config view (key/file/version table + JSON preview + Copy/Check)` in `game/addons/remote_config_editor/dock.gd`
- file `NEW: EditorToolPlugin _config (panel 'Remote Config'; no bridge)` in `game/addons/remote_config_editor/plugin.gd`
- class `NEW: DailyMissionsService (single-target save + rename cascade)` in `game/addons/daily_missions_editor/daily_missions_service.gd`
- file `NEW: Daily Missions view (mission tree + 7-day rotation grid + id readout)` in `game/addons/daily_missions_editor/dock.gd`
- class `MODIFY: hoist ICON_GLYPHS here as the one allowed-icon source` in `game/ui/screens/daily_missions_model.gd`
- file `MODIFY: read Model.ICON_GLYPHS instead of a local copy` in `game/ui/screens/daily_missions_panel.gd`
- class `MODIFY: remove check_catalog_sync/copy_publish_payload; KEEP CANONICAL_REL + save` in `game/addons/story_map_editor/story_map_service.gd`
- file `MODIFY: remove the Remote Config tab + helpers; rewrite the post-save hint` in `game/addons/story_map_editor/dock.gd`
- file `APP_CONFIG_VERSION cross-checked against the manifest; client read contract (CATALOG_KEY/DAILY_MISSIONS_KEY)` in `game/net/remote_config_client.gd`
- file `NEW verifier: manifest/build_document/versions/validate/payload (pure surface)` in `game/tools/verify_remote_config_service.gd`
- file `NEW verifier: CRUD/rename-cascade/validate/serialize-stability/save rollback` in `game/tools/verify_daily_missions_service.gd`
- file `UPDATE: publish instructions point at appconfig.ts (+ the BYOSnap deploy wiki page's status pre-flight gate)` in `validator/README.md`

## Data model
**The registry — `validator/content/app_config.manifest.json`** — is the single source of truth read by *both* the GDScript Remote Config tool (via `ContentStore.load_json`) and the TS `appconfig.ts`, so the editor table, the built payload, and the live verify can never disagree on the key set. Shape: `{ app_config_version, entries: [{ key, file, version_field, label }] }` (full example in *Design notes*).

- `key` — the app-config sibling key (`config.<key>`).
- `file` — path relative to `validator/content/`.
- `version_field` — the integer version field *inside* that blob (`story_catalog` uses `catalog_version`, `daily_missions` uses `version`; the manifest **adapts** rather than forcing a rename that would ripple through GDScript + golden tests).
- `app_config_version` — the Remote Config **document** version (`"v1"`, the URL segment), *distinct* from each block's **content** version. One source; it MUST equal `MbRemoteConfigClient.APP_CONFIG_VERSION` — enforced by a verifier, not just asserted.

Content files are read by `appconfig.ts` at runtime via `Bun.file(url).json()` (dynamic — the path is only known per-row), mirroring `sync-catalog.ts`; **not** static `import … with { type: "json" }`, which needs a literal path. A missing committed manifest **hard-fails** on both sides — no hardcoded fallback key list (a fallback would re-introduce the drift the manifest exists to kill).

**`daily_missions.json`** (what the Daily Missions tool authors): `{ enabled, version, anchor, by_weekday{"0"…"6":[ids]}, catalog{ id:{title,icon,desc,reward} } }`. Single committed target — **no baked `res://` copy** (unlike the story catalog it is not in the determinism/parity domain; the client reads the live block from Remote Config, and the feature is simply off when the block is absent). Allowed icons = the keys of `MbDailyMissions.ICON_GLYPHS` (hoisted from the panel to the model as one source of truth; the `""` fallback glyph is render-only and invalid for an authored entry).

## Usage
**Author Daily Missions.** Open the *Daily Missions* panel → add/edit missions (title, icon, description, reward) → set the anchor and the 7-day rotation grid → *Validate* → *Save*. Writes `validator/content/daily_missions.json`; `version` auto-bumps when content changed. *Copy ids* exports the canonical mission-id list for manual Quest provisioning in the Snapser console.

**Author Story Map.** Unchanged — *Catalog* + *Map dots* tabs; *Save all* writes the 3 files incl. `validator/content/story_catalog.json`. (The *Remote Config* tab is gone.)

**Publish to Remote Config.** Open the *Remote Config* panel → it shows a key / file / version / present table for every registered block and a live preview of the full `app-config/v1` document → **Copy publish payload** (the *whole* document) → paste into the Snapser console App Config under version `v1` → **Check sync** (per-key drift; shells out to `bun appconfig.ts verify --json`). CLI equivalents: `bun run appconfig:emit | pbcopy`, `bun run appconfig:verify`, `bun run appconfig:status`.

**Add a new block (e.g. `daily_login`) end-to-end.** (1) create `validator/content/daily_login.json`; (2) append one row to `app_config.manifest.json`; (3) add the client `DAILY_LOGIN_KEY` const + `extract_daily_login()` in `net/remote_config_client.gd`; (4) wire the runtime consumer; (5) add a verifier. Step 2 makes the block appear in the Remote Config tool automatically — but it does *not* create the other four, so the checklist is explicit.

## Invariants & constraints
- Each per-feature content tool writes ONLY its own validator/content/<key>.json blob; Remote Config aggregation, publish, and verify live solely in the Remote Config tool. No content tool reaches across feature boundaries (Story Map has no RC tab).
- build_document() in RemoteConfigService is the single pure aggregation point: it reads only the manifest + loaded blobs (no IO/clipboard/exec), returns {key: blob} in manifest order, and is asserted directly by the headless verifier.
- Every copy-to-clipboard / emit path produces the WHOLE multi-key document, never a single key — so a console paste of app-config/v1 cannot silently drop a sibling block. This is what closes the manual-merge footgun; no single-key copy path is left anywhere.
- The set of keys/files/version-fields and the document version live in exactly ONE committed file (app_config.manifest.json), read by both the GDScript Remote Config tool and appconfig.ts. A missing manifest hard-fails on both sides — there is no hardcoded fallback key list.
- app_config.manifest.json.app_config_version == MbRemoteConfigClient.APP_CONFIG_VERSION, asserted by a verifier (not left implicit) — the publisher and the client can never target different Remote Config document versions.
- The canonical key-order-insensitive comparator (canonical()/deepEqual) is defined ONCE, in appconfig.ts; the Remote Config tool's Check Sync shells out to it and never reimplements the compare in GDScript.
- appconfig.ts uses explicit presence checks ((key in live); typeof committed[version_field] === 'number'), never coercing a missing or zero version to 0 — so a block legitimately at version 0 (e.g. a fresh daily_login) is not misreported as absent/drifted.
- emit FAILS LOUD (exit 2) if any registered entry's file is missing or unparseable — it never prints a partial document; the GDScript Copy is gated on validate() for the same reason.
- Every editor tool obeys the Editor Tool Framework invariants: a headless-safe ToolService (no Control/EditorInterface refs), all writes through ContentStore (validate -> atomic N-target write -> rescan, with version-bump rollback), the {ok, error} return contract, method-callable signal binds, and an optional/no BridgeServer.
- The Story Map refactor is a pure subtraction: its 3-file save (baked + canonical + layout), serializers, and catalog_version bump are byte-for-byte unchanged, validator/content/story_catalog.json is still emitted on every save, and verify_story_map_service.gd passes unchanged.
- daily_missions.json is a single committed target (no baked res:// copy); its allowed icon set is MbDailyMissions.ICON_GLYPHS (one definition shared by the runtime panel, the editor picker, and validate()); a mission rename cascades into the catalog key, every by_weekday array, and the anchor so no dangling id survives.

## Synced commit
35c1d365ab7dc164d3b4f6110f2e2483c79e7c3b
