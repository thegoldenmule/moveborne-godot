# Spec — Player Profile &amp; Settings Screen

**Status:** sealed

## Overview
Design for surfacing and editing the player profile inside a real Settings screen. The Settings tab (app_shell index 4) stops being a `placeholder_tab` stub and becomes `settings_tab`, hosting two zones: a **Profile** zone backed by the Snapser Profiles snap (editable display name = canonical handle, preset avatar pick, identity readout) and a **Client settings** zone (audio/SFX, haptics, account/sign-out) persisted locally. Networking reuses the existing transient-HTTPRequest + gateway-auth-header pattern; no game/logic/ changes, so determinism parity is untouched.

## Design
## Surface & navigation

Settings stays a flat radio tab in app_shell (index 4, alongside Collection/Leaderboard/Home/Guilds), not a pushed UiRouter state. The shell already instantiates a screen per tab and toggles visibility; we swap PlaceholderScene for a new SettingsScene at that index. The screen builds its widgets in _ready() (the home.gd / leaderboard_tab.gd convention) and is handed the MbSnapserAuth instance via setup(_auth) exactly like leaderboard_tab. Profile is lazy-fetched on first tab-select (or on each select with a short cache) so the shell boot path stays synchronous and offline-safe.

## Profiles snap contract

All calls go through the gateway base https://gateway.snapser.com/c4n1awfs with auth headers Token + User-Id (MbSnapserAuth.auth_headers()). The snap stores a developer-defined JSON object per user; there are no hardcoded fields, so the attribute schema must be configured in the Snapser admin tool before the client can read/write meaningfully.

```text
GET   /v1/profiles/user/{user_id}      -> { "profile": { ... } }   (own private + others' public)
PUT   /v1/profiles/user/{user_id}      body { "profile": { ... } } -> {}      (upsert, full)
PATCH /v1/profiles/user/{user_id}      body { "profile": { ... } } -> { "profile": {...} } (partial)

user-auth scopes writes to the caller's own user_id (gateway-bound). api-key/internal can write any.
```

```json
// Proposed profile shape (attributes configured in Snapser admin):
{
  "profile": {
    "display_name": "Nyx",          // text, unique?, searchable, public, required
    "avatar_id": "arcana_moon",     // text or single-select, public
    "title": ""                      // optional flavor text, public
  }
}
```

## MbProfileClient (game/net/profile_client.gd)

A thin client mirroring leaderboards_client.gd: holds a reference to MbSnapserAuth, exposes async fetch_profile(user_id) and save_profile(patch) using a transient HTTPRequest, and keeps static, unit-testable helpers for URL and body construction plus response parsing. PATCH is preferred for edits (send only changed keys); PUT/upsert seeds the profile on first creation.

```gdscript
class_name MbProfileClient
extends Node

static func profile_url(user_id: String) -> String:
    return MbSnapserAuth.GATEWAY + "/v1/profiles/user/" + user_id

static func profile_body(attrs: Dictionary) -> String:
    return JSON.stringify({ "profile": attrs })

static func parse_profile(data) -> Dictionary:
    if typeof(data) == TYPE_DICTIONARY and data.has("profile"):
        return data["profile"]
    return {}

func fetch_profile(user_id: String) -> Dictionary: ...   # GET, transient HTTPRequest
func save_profile(user_id: String, attrs: Dictionary) -> bool: ...  # PATCH
```

## Settings screen layout

Vertical sections, occult-arcade styling via MbStyle + moveborne_ui.tres. (1) Profile: avatar tile + display-name LineEdit with a Save affordance and inline status (saving / saved / error / name-taken); identity readout (user id short, member-since) below. (2) Avatar picker: a grid of preset tiles; selecting one stages avatar_id, saved with the profile. (3) Client settings: audio + SFX volume sliders, haptics toggle. (4) Account: signed-in username, user id, Sign out. The Profile + Avatar sections hide or go read-only when there is no Snapser session.

## Display name as the canonical handle

Today leaderboards_client submits score_body(score, MbSnapserAuth.username()) where username() is the generated godot-XXXX handle. After this feature the profile display_name is the source of truth: the leaderboard submission reads the cached profile display_name (falling back to username() only when no profile/session). On first profile creation we seed display_name from the current username() so existing-style names don't regress to blank, then let the player rename.

## Avatar presets

Avatars are a fixed preset set, not uploads: the profile stores an avatar_id string and the client maps it to a local texture (assets/generated/icons or a new artgen batch). An unknown/empty avatar_id renders a default sigil. This keeps the snap schema trivial (one string) and avoids any image-upload/storage path.

## Client settings persistence

Audio/SFX/haptics are LOCAL device prefs, not profile attributes. Persist them to user://settings.cfg via ConfigFile, load on boot, and apply (e.g. AudioServer bus volumes). They function fully offline and never touch the network.

## Offline / no-session degradation

Infinite mode is always offline and Story/PvP may fail to reach Snapser. The Profile and Avatar sections must check MbSnapserAuth for a valid session and, when absent, render read-only or hidden with a short note instead of issuing requests or awaiting indefinitely. Client settings + account-local info remain available.

RESOLVED (assets committed): the preset set is 12 occult-arcade skull glyphs generated via artgen (icon-flat, violet line art on black, bg stripped) and saved into the project. avatar_id is the filename stem skull_avatar_01..skull_avatar_12; an unknown/empty id renders a default sigil. The picker maps avatar_id -> res://assets/generated/icons/<avatar_id>.svg.

```text
Avatar preset set (avatar_id -> asset):
  skull_avatar_01 .. skull_avatar_12
  -> res://assets/generated/icons/skull_avatar_{01..12}.svg

Default when avatar_id is empty/unknown: default sigil (fallback).
```

## Decisions
BLOCKER / first step: confirm the Profiles snap is enabled on snapend c4n1awfs (Snapser console or snapctl) before any client code. If it is not provisioned, add + redeploy the snapend first. No settings_tab networking lands until this is green. Is the Profiles snap actually provisioned/enabled on snapend c4n1awfs right now? Need to confirm via Snapser console or `snapctl` (the snap exists in vendored docs but has zero current game integration). If not provisioned, add it before any client work.

Proposed attribute schema (pending approval): display_name (text, searchable, public, required), avatar_id (text, public), title (text, public, optional). Keep it to these three to stay well under the 10-unique / 10-searchable limits. Confirm the exact attribute schema to configure: proposed display_name (text, unique, searchable, public, required) + avatar_id (text or single-select, public) + optional title/bio (text, public). Approve or adjust.

Proposed: ship a small fixed preset avatar set. Reuse existing assets/generated/icons where they fit the occult-arcade look; only commission a fresh artgen batch if the existing set is too thin. Stored as avatar_id string -> local texture map; unknown id renders a default sigil. Avatar source: generate a fresh occult-arcade preset avatar set via the artgen pipeline, or reuse/adapt existing generated icons under assets/generated/? This drives an art task vs none.

Proposed for v1: do NOT enforce display_name uniqueness (regular searchable attribute, duplicates allowed) to avoid a 'name taken' failure path on every edit. Revisit if/when profiles become public-facing. If product wants uniqueness, mark it unique and the edit UI must surface a collision error. Display-name uniqueness: enforce as a Profiles `unique` attribute (collisions rejected → edit must handle 'name taken' UX), or allow duplicate display names? Product call.

Proposed: no leaderboard backfill. The canonical display_name applies to scores submitted going forward; historical entries keep their stamped name. Seeding new profiles from the existing godot-XXXX username (below) keeps continuity without a migration job. Leaderboard backfill: when display_name becomes the canonical handle, do existing leaderboard entries (submitted under godot-XXXX) need migration/backfill, or does the new name only apply to scores submitted going forward?

Decided: on first profile creation, seed display_name from the current MbSnapserAuth.username() so leaderboard names never regress to blank, then allow rename. Leaderboard submission reads profile display_name, falling back to username() when no profile/session. Default display_name on first profile creation: seed it from the existing godot-XXXX username so leaderboard names don't regress to blank, then let the player rename? (Proposed: yes.)

## References
_None._

## Child pages
_None._
