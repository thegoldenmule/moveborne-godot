# ADR-16: Adopt Snapser as the online backend, replacing Nakama

**Status:** accepted

## Metadata
- **Date:** 2026-06-09
- **Scope:** Client / Server / Networking / Deployment
- **Deciders:** Benjamin Jordan

## Context
ADR-4 (Defer Nakama; ship local-authoritative single-player first) deferred Nakama but assumed it would be the eventual online backend (device auth, matchmaking, glicko2, leaderboards, economy) with the Validator alongside it — Nakama signing match starts and accepting validated moves. That assumption is now retired: the project switches to **Snapser**, a managed BaaS where you compose first-party *snaps* (Auth, Inventory, Leaderboards, Quests, …) into a *snapend* behind a single gateway, and bring custom services as *BYOSnaps* (containers the gateway fronts under a base path). The Validator is already a self-contained Bun/Hono/Socket.IO service, so it maps onto a BYOSnap with no rewrite, and Snapser's Auth snap supplies sign-in off the shelf — making the bespoke Nakama match-handler work unnecessary. Target is mobile-only (no web export).

## Decision
Switch the online backend from Nakama to Snapser. The game signs in through Snapser's Auth snap (anonymous login, PUT /v1/auth/login/anon) to obtain a user session; the session is cached client-side and reused across launches. The Validator deploys as the BYOSnap 'byosnap-validator' on snapend c4n1awfs, served through the gateway at https://gateway.snapser.com/c4n1awfs/v1/byosnap-validator. The client talks to that one base URL for both HTTP match-init and the Socket.IO transport.

Mode policy: Story (and future PvP) always play online against the deployed Validator; Infinite is always offline (pure local engine, no sign-in). Because the target is mobile-only, the client may use a native WebSocket with custom handshake headers (no browser same-origin / header restrictions to design around). This supersedes the backend-platform choice in ADR-4; that ADR's local-authoritative-first sequencing still stands and is unaffected.

## Consequences
POSITIVE: Managed auth, matchmaking, leaderboards, and economy come from off-the-shelf snaps instead of a hand-written Nakama runtime module. The Validator runs unchanged as a BYOSnap; the determinism contract is now proven end-to-end against the real gateway (anon login, match-init, Socket.IO, validated swipe). A clean dev iteration loop exists via snapctl byosnap direct-deploy to the development snapend.

NEGATIVE / COST: Vendor lock-in to Snapser's gateway-plus-snap model. The Validator must serve every route under the gateway base path it is given (the gateway forwards the prefix without stripping it) and answer an unprefixed /health for the platform probe. Build and deploy now require Docker plus snapctl and an arm64 image. The reusable Nakama infra (web3 wallet, glicko2) is dropped, not migrated. Staging and prod deploys differ from the dev direct-deploy path: they go through snapctl byosnap publish with a real semantic version and a strong validator shared secret.

## Relations
_None._
