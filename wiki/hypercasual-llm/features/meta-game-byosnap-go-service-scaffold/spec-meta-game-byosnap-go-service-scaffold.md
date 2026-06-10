# Spec — Meta-Game BYOSnap — Go service scaffold

**Status:** drafting

## Overview
A new top-level `metagame/` directory holds a Go HTTP service deployed to Snapser as **`byosnap-metagame`** — the skeleton of the meta-game service proposed on Design > General. This feature delivers *connectivity proof only*: a player client can reach the service through the gateway with a session token, and the service can reach a snap over gRPC with internal auth. Everything else (quests, economy, offers, User Auth Restrictions) is explicitly later work.

## Design
## Service surface

Exactly three routes. GET /health answers 200 unprefixed (the platform readiness probe hits it without the base path) and also under the base path, mirroring the validator. The two proof endpoints live under the gateway-forwarded base path (the platform-provided base-path environment variable, e.g. /v1/byosnap-metagame), which arrives unstripped.

GET {base}/ping proves client-to-service connectivity through the gateway. It requires a gateway-validated session: the handler reads the gateway-stamped User-Id header and returns it with a static ok marker and the service version. A request lacking the header gets a 401. This makes the response self-evidencing: seeing your own user id back proves the full client, gateway-auth, BYOSnap path.

GET {base}/snap-check proves service-to-snap connectivity. The handler dials the Auth snap's internal gRPC endpoint using the generated client from the snapser-pb auth package, invokes one read-only RPC, and returns a small JSON envelope: which snap and RPC were called, round-trip duration, and the upstream status. Failures return 502 with the gRPC status text so a broken internal path is diagnosable from the client side.

## Project setup

metagame/ is a self-contained Go module (Go 1.22 or later), structured as cmd/server/main.go plus small internal packages (http handlers, snap client wiring, config). Configuration comes only from environment variables already established by the platform and the validator precedent: the port (8080), the base path, the internal-auth header value, and whatever internal snap address variables Snapser provides. No config files.

The snapser-pb directory gains a minimal go.mod (module snapser-pb) and is otherwise untouched; metagame consumes it with a local replace directive in its own go.mod. Because every generated package is named proto, each per-snap directory is imported under a distinct alias (authpb, inventorypb, leaderboardspb, questspb). Only the auth client is exercised in this feature; the rest compile in for free.

## Auth model

Identity follows the accepted ADR (gateway-stamped User-Id): the service trusts the User-Id header the gateway binds after validating the player's JWT, and performs no token validation of its own. Calls from the service to snaps use internal auth (the Gateway: internal convention, with the header value supplied by the platform environment) — no API keys are minted for this feature. Local development self-stamps User-Id exactly as the validator tooling does.

## Deployment

A multi-stage Dockerfile builds a static linux/arm64 binary (golang builder stage, scratch or distroless runtime stage) with build context at the repo root so both metagame and snapser-pb are visible to the build. A snapser-byosnap-profile.json mirrors the validator's: external http port 8080, readiness probe on /health with a short initial delay, dev-template sizing at the validator's floor (0.25 vCPU, 0.25 GB, 1 replica).

Rollout: snapctl publishes the image as byosnap-metagame under app c4n1awfs, then the snapend is updated to attach it alongside byosnap-validator. Verification is through the gateway only: anonymous login (snapser-validator skill pattern), then ping with the session token, then snap-check. The deployed health probe staying green is the platform-side acceptance signal.

## Out of scope

All meta-game functionality (quests, missions, login bonuses, gacha, ad verification), User Auth Restrictions configuration, any write to any snap, adding new snaps to the snapend, Hermes/websocket integration, and any client (Godot) integration beyond the smoke test.

## Decisions
snap-check targets the Auth snap with one read-only RPC: it is the only snap guaranteed present in the snapend today and its stubs ship in the snapser-pb auth package. Inventory becomes the second target only after that snap joins the snapend (out of scope here). Which snap should the snap-check endpoint call to prove internal gRPC connectivity, given the snapend's current composition?

The snapser-pb directory is consumed as a local Go module: add a minimal go.mod (module snapser-pb), reference it from the metagame module with a replace directive, and alias each per-snap package at the import site since all generated packages are named proto. Generated files stay byte-identical to what Snapser produced. How should the module consume snapser-pb/, which has no go.mod and declares every package as `proto`?

Resolved from the intra-snapend networking docs: each snap exposes internal URLs injected into the BYOSnap environment as per-snap env vars — an HTTP URL on port 8090 and a gRPC URL on port 8080, host service-<snap> (so service-auth:8080 for the Auth snap), reachable only inside the snapend network. The service reads the Auth gRPC address from the platform-injected env var rather than hardcoding it. Residual check during implementation: the documented internal-call example is HTTP and passes the internal-auth header value as the gateway header; confirm whether gRPC needs the same value as call metadata — if internal gRPC is blocked without it, attach it; the internal HTTP surface on port 8090 remains the fallback with both endpoint contracts unchanged. Does the internal gRPC endpoint for snaps require ports/URLs not exposed in the docs we have vendored (the docs mention downloading Protos and internal snap URLs but not the address scheme)? May need the Snapser portal or support to confirm during implementation.

## References
_None._

## Child pages
_None._
