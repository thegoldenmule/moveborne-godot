# Implementation plan — Player Profile &amp; Settings Screen

**Status:** draft

## Steps
- [x] Confirm Profiles snap is provisioned on snapend c4n1awfs (snapser MCP list_snaps / console). If absent, add it and update the snapend. BLOCKER for all following steps.
- [x] Configure profile attributes in the Snapser admin tool per approved schema (display_name / avatar_id / title). Note their access (public) + searchable flags.
- [x] Smoke-test the live endpoints with the snapser-validator skill token: GET then PATCH /v1/profiles/user/{user_id} against the gateway, confirming auth headers + body shape {"profile":{...}} round-trip.
- [x] Add MbProfileClient (game/net/profile_client.gd): static helpers profile_url / profile_body / parse_profile + async fetch_profile() and save_profile() via transient HTTPRequest, mirroring leaderboards_client.gd.
- [x] Add a headless verifier for the static helpers (tools/verify_profile_client.gd or an McpTestSuite case): URL/body construction + parse_profile, following the validation/validator-client verifier pattern.
- [x] Create settings_tab.tscn + settings_tab.gd; wire app_shell index 4 to instantiate it instead of placeholder_tab, and pass _auth via setup() like leaderboard_tab. Keep it a flat tab.
- [x] Build the Profile section UI: avatar tile + display-name LineEdit + Save with inline status; identity readout. Lazy-fetch profile on tab-select; seed display_name from username() on first creation.
- [x] Build the avatar picker: preset grid mapping avatar_id <-> local texture; selection stages avatar_id, persisted with the profile PATCH. Default sigil for unknown/empty id.
- [x] Build client settings section: audio + SFX volume sliders + haptics toggle, persisted to user://settings.cfg (ConfigFile), loaded on boot and applied to AudioServer buses.
- [x] Build account section: signed-in username + user id readout + Sign out action (clear cached session).
- [x] Wire display_name as canonical handle: leaderboard score submission reads cached profile display_name, falling back to username() when no profile/session. Broadcast a profile-changed signal so dependent surfaces refresh.
- [x] Implement offline/no-session degradation: profile + avatar sections read-only/hidden without a valid Snapser session; guard all awaits; client settings remain functional.
- [x] Style pass to MbStyle + moveborne_ui.tres / art STYLE_GUIDE; screenshot via godot-ai editor_screenshot for review.
- [ ] Verify no game/logic/ files changed (determinism parity untouched); run the existing parity verifiers as a sanity check; manual end-to-end: edit name + avatar, confirm persistence across relaunch and that the leaderboard shows the new name.

## Data models & interfaces
```gdscript
# Cached profile on GameState (or a small Profile autoload)
var profile := {
    "display_name": "",   # canonical handle; seeded from username() on first create
    "avatar_id": "",      # preset id -> local texture; "" => default sigil
    "title": "",          # optional flavor text
}
signal profile_changed(profile: Dictionary)

# Local device settings (user://settings.cfg via ConfigFile) -- NOT in the snap
# [audio] master=1.0  sfx=1.0
# [haptics] enabled=true
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
