# Snapend Provisioning (snapctl IaC)

**Status:** current

## Kind
subsystem

## Summary
How the built-in Snapser snaps on the dev snapend `c4n1awfs` (Quests, Remote Config, Inventory, …) are **configured as Infrastructure-as-Code via the snapend manifest + `snapctl snapend apply`** — not console-only. There is no per-definition write API; `snapctl snap-config get-config` is **read-only**, and the snapend manifest (`snapser/snapend-manifest.json`) is the single editable, version-controlled source. Each snap's config lives under `settings[id=<snap>].data` (e.g. quests → `data.quests[]`). **Live:** the 7 Daily Missions `daily_mission` quests were provisioned this way and verified end-to-end (commit `a00d0c1`, snapend v27).

## Purpose
Built-in snap definitions (quest definitions, Remote Config app-configs, inventory currencies) can be authored in the Snapser console UI, but they are equally writable through the **snapend manifest**, which is Snapser's own IaC. Driving them via `snapctl snapend apply` lets an agent or CI provision them **reproducibly**, keep them in **source control**, and review them as a diff — instead of hand-clicking a console form per quest. This matters because the metagame is quest-driven (Daily Missions now; Daily Login Bonus next), so the same provisioning path is reused per feature. The catch: the manifest is large and shared (the whole snapend), `apply` mutates the live dev backend, and the committed copy drifts the moment anyone edits via the console — so the discipline below (download-fresh, apply, re-download, commit) is load-bearing.

## Design notes
Daily Missions worked example (commit a00d0c1). Seven quests on c4n1awfs, all tagged daily_mission, type recurring, cron 0 0 * * *, Counter (delta/gte) tasks, coin quest-rewards: mission_anchor_play_3 (auto_assign ON, task matches_played goal 3, 100 coins) + six pool quests with auto_assign OFF (mission_win_2/matches_won/2/150, mission_play_5/matches_played/5/150, mission_score_5k/match_score/5000/120, mission_combo_5/merge_size/5/120, mission_powerup_2/powerups_used/2/80, mission_merge_50/tiles_merged/50/100). The anchor is auto-assigned by GetActiveQuests; the pool subset is assigned per UTC weekday by the client via AssignQuest. Quest ids must equal the daily_missions.json catalog keys so the client maps each to its display title/icon/reward.

Verified end-to-end with a throwaway anon user (the canonical way to prove a quest config): anon login -> GET active_quests?tags=daily_mission auto-assigns the anchor -> PUT IncrementTaskProgress (delta to goal) completes the task -> POST ClaimQuestRewards returns currencies_granted {coins:100} -> GET inventory currencies shows coins:100. Reward grant + inventory credit both work.

inventory.quest_callback_currencies is NOT the reward path. It is the inventory->quests callback that auto-advances Currency-GOAL-type tasks ("acquire 10 gold"), which Daily Missions does not use (all goals are Counter/delta). Currency REWARDS are granted by the quest's reward_currencies via ClaimQuestRewards and only require the currency to exist in inventory.currencies (coins does). Confirmed: rewards granted + credited with quest_callback_currencies left empty. Do not confuse this with the inventory currencies wallet list (a separate field that DID need coins, fixed earlier).

```bash
# Provision/extend quest definitions on the dev snapend (IaC):
snapctl snapend download --snapend-id c4n1awfs --category snapend-manifest \
    --format json --out-path /tmp/snap
# edit /tmp/snap/snapser-c4n1awfs-manifest.json: settings[id=quests].data.quests[]
snapctl snapend apply --manifest-path-filename /tmp/snap/snapser-c4n1awfs-manifest.json --blocking
snapctl snap-config get-config --snaps quests --snapend-id c4n1awfs   # read-only verify
# then re-download and commit snapser/snapend-manifest.json
```

Client increment hook (commit 0eb4923). Match progress feeds the quests via MbDailyMissions.match_task_increments (a pure, headless-tested mapper) + DailySigil.record_match_result, fired once per banked result from AppShell on post-match resume (and StoryMapState level-chaining), guarded by a dm_recorded flag and a live session (inert offline / in Infinite). Per-match tallies — tiles merged, largest single-swipe merge (from the engine's mergedTilesCount), power cards played — are accumulated in MbMatch (game/, NOT hashed; reset on new_game*) and ride the match_exited result alongside score + story stars. Metric->task-name contract: matches_played / matches_won / tiles_merged / powerups_used are CUMULATIVE (+= amount); match_score and merge_size are "in a match" THRESHOLDS (+= the task goal once a single match meets it). Completed tasks are skipped. So the task NAMES authored on the quests are the integration contract between the snapend config and the client.

## Components
_No components._

## Dependencies
- **depends-on** → [Remote Config & Content Authoring](architecture:mqjk73oh-03px-m87rim) — The Remote Config app-config half (story_catalog + daily_missions blocks) is published by the manifest/appconfig pipeline documented there; this node covers the Quests/Inventory snap config side.
- **depends-on** → [Deploying the Validator (BYOSnap)](architecture:mqh6jhyd-0095-4qhwpw) — Sibling snapend-ops runbook (deploying the validator BYOSnap); same c4n1awfs snapend + snapctl tooling.

## Code references
- file `snapend IaC source of truth (settings[id=quests].data.quests[], inventory currencies, remote-config app_configs)` in `snapser/snapend-manifest.json`
- file `Remote Config app-config publish/verify (sibling provisioning path)` in `validator/src/validator/tools/appconfig.ts`
- file `app-config key registry feeding appconfig.ts` in `validator/content/app_config.manifest.json`
- class `MbQuestsClient — the runtime consumer (active_quests by tag, assign, increment, claim)` in `game/net/quests_client.gd`

## Data model
**Per-snap config slots** in `snapser/snapend-manifest.json` (`settings[]`, one entry per snap): `auth`, `inventory` (`currencies`, `quest_callback_currencies`, …), `leaderboards`, `profiles`, `quests` (`quests[]`), `remote-config` (`app_configs`, `base_config`, `overrides`), `storage`.

**Quest definition object** (`settings[id=quests].data.quests[]`, read back from a console-created quest):
- top level: `name` (unique id — the client matches it to the `daily_missions` catalog key), `description`, `tags:[]`, `all_users`, `segment`, `auto_assign`, `is_active`, `type:"recurring"`, `cron_expr` (e.g. `"0 0 * * *"`), `metadata`, and reward arrays `reward_currencies:[{name,count,count_64}]` / `reward_{drop_tables,energy,inventory_items,statistics,xp}`.
- `tasks:[{ name, description, goal, goal_64, goal_type:"delta", comparison_type:"gte", goal_sign:"positive", auto_progress:false, metadata, reward_*:[], tracking_object_name, tracking_object_type }]`.

The console's **"Counter"** goal maps to `goal_type:"delta"` + `comparison_type:"gte"` + `auto_progress:false` — a snap-tracked counter the client advances via `IncrementTaskProgress`. A quest's currency **reward sits at the QUEST level** (`reward_currencies`), because the client claims via `ClaimQuestRewards`, not task-level claims.

## Usage
**Provisioning flow (download → edit → apply → verify → commit):**

1. **Download fresh** (the committed copy goes stale): `snapctl snapend download --snapend-id c4n1awfs --category snapend-manifest --format json --out-path <dir>` → writes `snapser-c4n1awfs-manifest.json`.
2. **Edit** the target snap's config slot, e.g. append to `settings[id=quests].data.quests[]`.
3. **Apply**: `snapctl snapend apply --manifest-path-filename <file> --blocking` (add `--force` only if config-diff validation complains). Waits until the snapend returns to **Live**; bumps the snapend `version`.
4. **Verify** (read-only): `snapctl snap-config get-config --snaps quests --snapend-id c4n1awfs`.
5. **Re-download + commit** `snapser/snapend-manifest.json` so the IaC source of truth matches live (the apply output literally reminds you to).

**Schema-discovery trick:** the config arrays start empty, and the definition JSON schema isn't in the (player-facing) swagger. Author **one** example in the console, read it back with `get-config`, then clone that exact object for the rest — never hand-guess keys for a forced apply to the shared backend.

**Remote Config app-config** is the sibling case: published either through the manifest's `remote-config.data.app_configs` or (as today) a manual console paste verified with `bun run appconfig:verify` — see the *Remote Config & Content Authoring* node.

## Invariants & constraints
- Built-in snap definitions (quests, app-configs, currencies) are provisioned via the snapend manifest + `snapctl snapend apply` (IaC). `snapctl snap-config get-config` is read-only; there is no per-definition write API.
- Always download the LIVE manifest fresh before editing (the committed snapser/snapend-manifest.json drifts whenever anyone edits via the console), and re-download + commit it after a successful apply so the IaC source of truth matches live.
- A quest's currency reward sits at the QUEST level (reward_currencies), because the client claims via ClaimQuestRewards; the console "Counter" goal maps to goal_type=delta + comparison_type=gte + auto_progress=false (client-driven via IncrementTaskProgress).
- The anchor quest is auto_assign ON (GetActiveQuests assigns it); pool quests are auto_assign OFF (the client AssignQuests the UTC-weekday subset). Quest ids must equal the daily_missions.json catalog keys for the client to map display metadata.
- inventory.quest_callback_currencies gates only Currency-GOAL task auto-tracking, NOT currency reward grants; currency rewards need only the currency in inventory.currencies. Empty quest_callback_currencies is fine for the Daily Missions setup (verified).
- The daily-mission quest task NAMES are the client integration contract: matches_played / matches_won / tiles_merged / powerups_used (cumulative) and match_score / merge_size ("in a match" thresholds). Renaming a task on the snapend without updating MbDailyMissions._metric_delta silently stops that mission from progressing.

## Synced commit
0eb4923f95d694629bad42fa7262f1e61f681f28
