# Feature: Player Profile &amp; Settings Screen

**Status:** shipped

## Summary
Turn the Settings tab — today an empty `placeholder_tab` stub at index 4 of the app shell — into a real screen whose centerpiece is the **player profile**, backed by the Snapser **Profiles snap**.

**Profile (server-backed, Profiles snap).** An editable **display name** that becomes the *canonical player handle*: it is the source of truth that feeds the leaderboard submission (`user_metadata.name`) and any future social surface, overriding the auto-generated `godot-XXXXXXXX` username. A **preset avatar pick** (occult-arcade icon set; stored as an `avatar_id` attribute, no upload). A read-only identity readout (user id, member-since).

**Client settings (local).** Audio / SFX volume, haptics toggle, and an account section (signed-in identity, sign-out) — persisted locally (`user://`), not in the profile.

**Integration shape.** Reuse the established Snapser HTTP pattern (transient `HTTPRequest` + `auth.auth_headers()` → `Token` + `User-Id`, through `https://gateway.snapser.com/c4n1awfs`), exactly as `inventory_client.gd` / `leaderboards_client.gd` do. Profile CRUD is `GET`/`PUT`/`PATCH /v1/profiles/user/{user_id}`. No `game/logic/` changes — pure UI + net, zero determinism impact. Must degrade gracefully offline (Infinite mode / no session): client settings still work; profile section goes read-only or hidden.

This is the first page under the **Features** TOC and the first real content for the Settings tab, which the App Shell & UI Router feature left as a deliberate stub.

## Components affected
- Profiles snap provisioning + attribute schema (Snapser admin / snapctl): confirm the snap is on snapend c4n1awfs and configure attributes (display_name, avatar_id, optional title)
- MbProfileClient — new GDScript net client (game/net/profile_client.gd): get / upsert / patch profile via /v1/profiles/user/{user_id}, transient HTTPRequest + auth headers, static URL/body/parse helpers (mirrors leaderboards_client.gd)
- Settings screen scene + script (game/ui/screens/settings_tab.tscn/.gd) replacing placeholder_tab at app_shell index 4; built in _ready() following home.gd / leaderboard_tab.gd
- Profile section UI: display-name edit field (with validation + save/feedback), avatar picker grid, read-only identity readout
- Avatar preset set: occult-arcade icon assets + avatar_id↔asset mapping (reuse generated icons or new artgen batch)
- Client settings section: audio/SFX volume sliders + haptics toggle, persisted to user://settings.cfg (ConfigFile), applied to AudioServer buses
- Account section: signed-in identity readout (user id / username), sign-out action, session info
- Display-name → leaderboard wiring: profile display_name becomes the source for leaderboard score submission, replacing MbSnapserAuth.username()
- Profile cache + change signal on GameState (or a profile autoload): lazy-load on tab select, broadcast display_name/avatar changes to currency bar / future surfaces
- Offline / no-session degradation: profile section read-only or hidden when MbSnapserAuth has no session (Infinite always-offline); client settings remain fully functional

## Design constraints
1. MUST NOT touch game/logic/ — this is pure UI + net, no determinism impact. No parity re-run needed beyond confirming no logic/ files changed.
2. Reuse the existing Snapser HTTP pattern: transient HTTPRequest node + MbSnapserAuth.auth_headers() (Token + User-Id) against GATEWAY = https://gateway.snapser.com/c4n1awfs. Do NOT invent a new HTTP wrapper unless a clear need emerges.
3. Profiles snap REST surface (from snapser-docs/swagger/profiles.swagger3.json): GET /v1/profiles/user/{user_id}, PUT (upsert) and PATCH (partial) same path; body shape {"profile": { ... }}; user-auth scopes writes to the caller's own user_id.
4. Profile attributes must be configured in the Snapser admin tool FIRST (the snap stores a developer-defined JSON schema, not hardcoded fields). Limits: max 10 unique, max 10 searchable attributes. display_name should be public + (likely) unique + searchable; avatar_id public.
5. Keep Settings a FLAT tab inside app_shell (like Collection/Guilds/Leaderboard), not a pushed UiRouter state — unless async profile load forces it. Prefer: lazy-fetch profile on tab-select within the tab screen.
6. Style via MbStyle constants (scenes/style.gd) + the moveborne_ui.tres theme; apply theme overrides programmatically in _ready(), matching home.gd / leaderboard_tab.gd. Occult-arcade violet-on-black per art/STYLE_GUIDE.md.
7. Sanitize/validate display name on the client before write (length bound, charset) — same defensive posture as the validator's input sanitization. Note the open user-auth self-grant hardening finding: a user-auth client CAN write its own profile directly, so treat client-side validation as UX-only, not a security boundary.
8. Settings screen must degrade gracefully with no Snapser session (Infinite is always offline; Story/PvP may fail to connect): client settings fully functional, profile section read-only or hidden, no crashes / hung awaits.
9. Client-local settings (audio/haptics) persist to user:// via ConfigFile — they are NOT profile attributes. Only display_name + avatar_id live in the Profiles snap.

## Open questions
_None._

## Resolved questions
1. **Is the Profiles snap actually provisioned/enabled on snapend c4n1awfs right now? Need to confirm via Snapser console or `snapctl` (the snap exists in vendored docs but has zero current game integration). If not provisioned, add it before any client work.** — _No — the Profiles snap is NOT currently provisioned on snapend c4n1awfs. It must be added to the snapend (and the snapend redeployed) before any client work. This is the first implementation step / hard blocker._
2. **Confirm the exact attribute schema to configure: proposed display_name (text, unique, searchable, public, required) + avatar_id (text or single-select, public) + optional title/bio (text, public). Approve or adjust.** — _Approved as proposed to start: display_name (text, searchable, public, required), avatar_id (text, public), title (text, public, optional)._
3. **Avatar source: generate a fresh occult-arcade preset avatar set via the artgen pipeline, or reuse/adapt existing generated icons under assets/generated/? This drives an art task vs none.** — _Use a 12-avatar preset set built from the artgen 'skull avatar' batches: keep the ~4 already generated and generate 8 more (12 total), mark them saved in the artgen ledger, and map avatar_id -> the saved textures._
4. **Display-name uniqueness: enforce as a Profiles `unique` attribute (collisions rejected → edit must handle 'name taken' UX), or allow duplicate display names? Product call.** — _Allow duplicate display names for v1 (regular searchable attribute, not unique) — no 'name taken' failure path. Revisit if profiles become public-facing._
5. **Leaderboard backfill: when display_name becomes the canonical handle, do existing leaderboard entries (submitted under godot-XXXX) need migration/backfill, or does the new name only apply to scores submitted going forward?** — _Forward only — no leaderboard backfill. Canonical display_name applies to scores submitted going forward; historical entries keep their stamped name._
6. **Default display_name on first profile creation: seed it from the existing godot-XXXX username so leaderboard names don't regress to blank, then let the player rename? (Proposed: yes.)** — _Yes — seed display_name from the current godot-XXXX username() on first profile creation, then allow rename; leaderboard falls back to username() only when no profile/session._

## References
_None._

## Child pages
- [Implementation plan — Player Profile &amp; Settings Screen](implementation-plan:mq9xkeg0-00a1-kxfcm8)
- [Testing plan — Player Profile &amp; Settings Screen](testing-plan:mq9xkeg0-00a2-hpm89g)
- [Spec — Player Profile &amp; Settings Screen](feature-spec:mq9xkeg0-00a3-jcbof5)

## Commits
- `4f30c74fb04495829fb17d175d4374c9a0628563` feat(ui): Player Profile in a real Settings screen (Profiles snap)
- `ca726839140f63606668622c51dfe39f4ba9e759` polish(ui): shared MbScreenScaffold for consistent tab-screen padding
- `4c582b22b6645fd19c82849d14f5e31a86a5b0a3` polish(ui): avatar picker as a modal overlay, not an inline grid
