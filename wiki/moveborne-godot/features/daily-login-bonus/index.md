# Feature: Daily Login Bonus

**Status:** shipped

## Summary
Reward the player for simply opening the game each day, on an **escalating day-1 → day-N calendar** — the cheapest retention lever on the meta-game roadmap.

**Snap mapping (all built-in, no BYOSnap code):** a recurring daily **Quest** is the once-per-day *gate*; a **Trackables `login_calendar` XP ladder** is the *escalation curve + reward table*; **Inventory** holds the granted currency; **Remote Config** carries the display calendar and tuning. The escalating calendar — the documented "not built in" gap — is *composed* from the ladder rather than written as custom logic.

**What changed since this was drafted (Daily Missions shipped — 2026-06-18):** the shared `MbQuestsClient`, the app-config manifest + the one generic `appconfig.ts` publisher, and the `editor_tool_kit` + `daily_missions_editor` in-editor authoring pattern now all exist. This feature is therefore no longer green-field plumbing — it *mirrors* Daily Missions: a `daily_login.json` Remote Config block, a **fully-functioning `daily_login_editor`** tool that authors it (the centerpiece of this build), a pure `MbDailyLogin` model, and a runtime claim screen that reuses the reward-reveal ceremony.

**Backend reality:** the **Trackables snap is NOT provisioned** on `c4n1awfs` (confirmed 2026-06-18 from `snapend-manifest.json`) — adding it via a snapend update is the one prerequisite the live grant path needs; the editor, content, model, and verifier all land and verify headlessly without it.

**Authority:** the gate is a client-tracked counter, so the worst case is one day's bonus — a *bounded daily mint*, acceptable at launch under the Authority Model. Harden to a trusted increment later.

## Components affected
- daily_login gate quest — recurring daily Quest, one counter task (goal = 1), reward grants +1 to the calendar ladder
- login_calendar Trackables XP ladder — one level per calendar day, each level grants that day's currency; auto-resets to loop the cycle
- Remote Config block daily_login — enable flag, cycle length, per-day display table, reward tuning
- Client reward-screen + calendar strip — assign, increment, claim, read new level, render today + upcoming days
- Trusted-increment hook (deferred) — move the once-per-day increment from client to validator/metagame for hardening
- daily_login_editor (editor_tool_kit tool — THE centerpiece) — service + dock + plugin authoring the single committed validator/content/daily_login.json: per-day calendar CRUD, currency/amount per day, enable flag, cycle length, reset-on-miss, validate(), a canonical serialize(), a version-bump save() via ContentStore, and a copyable provisioning readout (the login_calendar ladder levels + the daily_login quest). Mirrors daily_missions_editor exactly; headlessly verified.
- MbDailyLogin model (daily_login_model.gd) — pure, headless-testable presentation logic shared by the runtime panel and the editor preview: is_enabled, the current calendar day derived from the login_calendar trackable level, today/upcoming strip data, claimed-vs-claimable state, reward formatting. Mirrors MbDailyMissions.
- trackables_client.gd (game/net) — reads the login_calendar level/progress through the Snapser gateway; static URL/parse helpers + a coroutine, mirroring quests_client.gd / leaderboards_client.gd. Inert (returns gracefully) until the Trackables snap is provisioned.
- Runtime login-bonus screen — a modal calendar strip (today highlighted, upcoming rewards previewed) + one Claim that claims the daily_login quest and runs the shared reward-reveal ceremony; orchestrated like daily_sigil, owned by AppShell, surfaced once per daily period on the Home surface.

## Design constraints
1. Quest rewards are claimed explicitly (ClaimRewardsForQuest); the Quests snap has no silent auto-grant — the claim IS the reward-screen tap.
2. The gate's counter goal is client-incremented at launch; blast radius is one day's bonus (bounded daily mint), acceptable per the Authority Model — harden to a trusted increment later.
3. Launch rewards are currency only — coins, souls, gems are provisioned; no Inventory catalog items exist yet.
4. Calendar advances by claims, not by consecutive calendar days: a missed day pauses progress, it does not reset. Punishing reset-on-miss is the separate Weekly Login Streak feature and needs custom logic.
5. Boundary is global UTC midnight (cron is server-side and global); per-player local midnight is not built-in.
6. Trackables level-reward grant-vs-claim semantics must be confirmed in the Settings tool so the client can surface a single 'Claim today's bonus' action.
7. The editor authors only the committed daily_login.json (the Remote Config DISPLAY calendar + tuning); the authoritative grant lives in the Trackables ladder. Neither Trackables nor Quests exposes a write API, so — exactly like Daily Missions — the editor emits a copyable provisioning readout (ladder levels + the daily_login quest) the operator pastes into the Snapser console. Publishing the RC block itself is the Remote Config tool's job: the manifest now aggregates daily_login alongside story_catalog + daily_missions.
8. Trackables is NOT provisioned on c4n1awfs — the live snaps are auth, inventory, leaderboards, profiles, quests, remote-config, storage, byosnap-metagame, byosnap-validator (confirmed 2026-06-18 from snapend-manifest.json). The login_calendar ladder backend does not exist yet; adding `trackables` via a snapend update is the prerequisite for any live end-to-end grant. All editor/content/model/verifier work is buildable and headlessly verifiable without it.
9. Reuse the shipped Daily Missions surfaces rather than re-plumbing: MbQuestsClient (assign / increment / claim) is shared; the editor mirrors daily_missions_editor; the runtime claim reuses daily_sigil's reward-reveal ceremony + GameState.add_currencies; the model mirrors MbDailyMissions; the content block rides the existing app-config document via remote_config_client (a new sibling key).

## Open questions
_None._

## Resolved questions
1. **Calendar length and reward curve: 7-day or 28-day cycle, and the exact per-day currency amounts?** — _Shipped as a 7-day cycle (cycle length = number of login_calendar ladder levels). Per-day rewards as shipped: 50 / 75 / 100 / 150 / 200 / 300 coins (days 1–6) then 20 gems on day 7 — placeholder tuning values, adjustable via the daily_login_editor (RC display) + the login_calendar ladder levels._
2. **On a missed day, pause-and-continue (recommended; fully built-in) or reset to day 1 (needs custom logic)?** — _Shipped pause-and-continue (reset_on_miss=false). The login_calendar ladder XP is durable and never resets on a missed day; only the daily quest resets at UTC midnight. Punishing reset-on-miss stays the separate Weekly Login Streak feature._
3. **Which currencies fund the bonus — coins for staple days with a gems capstone on the final day?** — _Shipped coins for the staple days (1–6) with a gems capstone on day 7 (50/75/100/150/200/300 coins → 20 gems). All four launch currencies (coins/souls/gems) are selectable per day in the editor; this is the launch curve._
4. **Backend escalation mechanism: keep the Trackables `login_calendar` XP ladder (requires provisioning the Trackables snap), or reframe to a pure Quests pool (one quest per calendar day, no new snap) now that Daily Missions proved that pattern in production?** — _Keep the Trackables `login_calendar` XP ladder (ratified 2026-06-18). It preserves the spec's elegant single-quest gate (one recurring daily_login quest whose only reward is +1 ladder progress, so the daily cron is the rate-limiter and the ladder supplies the per-day escalation). The cost is one prerequisite: adding the Trackables snap to the snapend before the live grant works. The editor, content block, model, verifier, and runtime UI are all built against this design and verify headlessly now; only the live end-to-end grant is gated on provisioning._

## References
_None._

## Child pages
- [Implementation plan — Daily Login Bonus](implementation-plan:mq9xf7gd-0084-1du6pg)
- [Testing plan — Daily Login Bonus](testing-plan:mq9xf7gd-0085-v1nsqi)
- [Spec — Daily Login Bonus](feature-spec:mq9xf7gd-0086-uo1jpm)

## Commits
- `199c8c9` feat(daily-login): editor + content + runtime claim flow (Trackables-ladder)
- `c159ddf` fix(daily-login): position by ladder level index, not raw XP (2-XP pitch)
- `70b2b79` chore(snapser): provision trackables snap + daily_login quest on c4n1awfs
- `8517d1f` chore(snapser): login_calendar ladder (console) + daily_login +2 XP/claim live
- `d402381` chore(snapser): complete login_calendar ladder to 7 days via snapctl (verified E2E)
