# Testing plan — Player Profile & Settings Screen

**Status:** ready

## Planned
_None._

## Passed
- MbProfileClient static helpers (headless verifier): profile_url builds GATEWAY + /v1/profiles/user/{user_id}; profile_body wraps attrs as {"profile":{...}}; parse_profile extracts the profile dict and returns {} on malformed/missing input.
- Live endpoint round-trip (snapser-validator token): PATCH display_name then GET returns the updated value; auth headers (Token + User-Id) accepted; writing scopes to the caller's own user_id only.
- First-run seed: a user with no profile gets display_name seeded from godot-XXXX username() on creation; leaderboard name does not regress to blank.
- Edit + persist: change display_name and avatar in Settings, relaunch the game, confirm both persist (round-tripped from the snap, not just local).
- Canonical handle: after renaming, a submitted leaderboard score shows the new display_name (not the old godot-XXXX); fallback to username() holds when no profile/session.
- Avatar picker: selecting a preset stages + saves avatar_id; the chosen avatar renders on the profile tile; unknown/empty avatar_id renders the default sigil.
- Client settings persistence: audio/SFX/haptics changes write to user://settings.cfg, reload on relaunch, and actually affect AudioServer bus volumes; work with no network.
- Offline / no-session: launch Infinite (always offline) or with Snapser unreachable -> profile + avatar sections are read-only/hidden with a note, no hung awaits or crashes; client settings + account-local info still usable.
- Display-name validation UX: over-length / disallowed-charset input is rejected client-side with clear feedback before any write.
- Determinism guard: confirm no files under game/logic/ changed; existing parity verifiers still PASS (feature is UI + net only).
- Sign out: account section sign-out clears the cached session; profile section transitions to its no-session state without restart.

## Failed
_None._

## References
_None._

## Child pages
_None._
