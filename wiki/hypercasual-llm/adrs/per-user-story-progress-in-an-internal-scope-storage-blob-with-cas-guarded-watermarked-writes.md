# ADR-24: Per-user story progress in an internal-scope Storage blob with cas-guarded, watermarked writes

**Status:** accepted

## Metadata
- **Date:** 2026-06-12
- **Scope:** validator + Snapser platform (durable per-user state)
- **Deciders:** Benjamin Jordan

## Context
Stars, unlocks, and reward watermarks must be server-authoritative per player and survive across sessions, while the validator keeps match state in-memory only. Snapser Storage allows user-auth writes to a player's own blobs by default — an unprotected progress blob is a watermark-reset re-farm vector. Daily Missions had established Quests + Remote Config for daily progression, so a deliberate choice was needed for durable story progression (decided 2026-06-12: Storage blob for story; Quests stays the dailies pattern — the two coexist).

## Decision
Progress lives in one Storage-snap json-blob per user (key story_progress, access protected), written ONLY by the validator via s2s on CompleteMatch; the game client is read-only and renders the map from it.

The blob key is provisioned with scope INTERNAL, so the platform itself rejects user-auth writes (401) while user-auth reads keep working — server-writable/client-readable is composed from blob-key scope, not Auth user-auth exemptions.

Writes are read-merge-write guarded by the Storage cas token. rewarded_stars is a monotonic watermark so replays grant only newly earned tiers; stars are max-monotonic; the unlock frontier is recomputed from catalog order and enforced server-side at completion (a locked level grades but neither grants nor persists).

A FAILED progress read aborts persistence and granting entirely (the grade is still reported, rewards withheld). A transient 5xx is never treated as no-progress-yet — merging against an empty default would overwrite the blob and reset every watermark.

## Consequences
Clients cannot forge stars or unlocks or re-farm rewards; verified live (user-auth PUT returns 401) and under concurrency (a cas-conflicted write withholds its grant, so completions cannot double-mint).

The watermark lands before the Inventory grants, so an Inventory s2s failure costs the player that tier's currency rather than risking a double-mint — the same stance as the original per-match rewards latch.

Storage blob keys are console-provisioned (the snapend-manifest settings-import shape is undocumented and apply attempts are rejected), so each new blob key is a manual step per environment.

This is the template for future server-authoritative per-user state (e.g. mission hardening): internal-scope blob + cas guard + monotonic watermark.

## Relations
_None._
