# Feature: Meta-Game BYOSnap — Go service scaffold

**Status:** planning

## Summary
Stand up the *meta-game service* proposed on Design > General as a deployed skeleton: a **Go** BYOSnap (`byosnap-metagame`) in a new top-level `metagame/` directory, reachable **through the Snapser gateway** with a player session token, and able to call other snaps over **gRPC** using the vendored stubs in `snapser-pb/`. Scope is strictly *creation and project setup*: the service exposes only enough surface to prove the two connectivity paths — (1) client → gateway → service, and (2) service → snap via internal auth — plus the platform health probe. No meta-game features (quests, economy, offers) ship in this feature. Deploying to Snapser (app `c4n1awfs`, alongside `byosnap-validator`) and smoke-testing through the gateway are part of the deliverable.

## Components affected
- metagame/ Go module — HTTP service with /health plus two proof endpoints (ping, snap-check)
- snapser-pb wiring — make the vendored package-proto gRPC stubs importable and dial a snap with internal auth
- Deployment artifacts — multi-stage Dockerfile (linux/arm64) + snapser-byosnap-profile.json mirroring the validator's
- Snapser rollout — snapctl publish to app c4n1awfs and snapend update attaching byosnap-metagame
- Gateway smoke verification — anonymous login + authenticated calls (snapser-validator skill pattern)

## Design constraints
1. Go only; ships as a single static binary in a multi-stage image (platform linux/arm64, listening on :8080, per the validator profile).
2. Scaffold only: exactly two proof endpoints plus /health — no meta-game logic, no User Auth Restrictions changes, no writes to any snap.
3. Snap calls go over gRPC using the generated stubs in snapser-pb/ (all declare `package proto`; no go.mod there today) — not the HTTP Internal SDK.
4. Gateway contract mirrors the validator: BYOSNAP_BASE_PATH arrives unstripped, /health must also answer unprefixed, and identity is the gateway-stamped User-Id header (per the accepted auth ADR) — no self-rolled auth.
5. Deploys as a second BYOSnap beside byosnap-validator; the validator and its deploy pipeline are untouched.

## Open questions
_None._

## Resolved questions
1. **Which snap should the snap-check endpoint call to prove internal gRPC connectivity, given the snapend's current composition?** — _Target the Auth snap with a read-only call. Auth is the one snap guaranteed in the snapend today (anonymous login already powers the validator flow), and snapser-pb/auth ships its stubs. Inventory is the natural second target later, but adding snaps to the snapend is out of scope for this feature._
2. **How should the module consume snapser-pb/, which has no go.mod and declares every package as `proto`?** — _Add a minimal go.mod to snapser-pb/ (module name snapser-pb) and consume it from metagame/go.mod via a local replace directive. Each per-snap directory is imported under a distinct alias (authpb, inventorypb, ...) since every generated package is named `proto`. Generated files are not modified._
3. **Does the internal gRPC endpoint for snaps require ports/URLs not exposed in the docs we have vendored (the docs mention downloading Protos and internal snap URLs but not the address scheme)? May need the Snapser portal or support to confirm during implementation.** — _Resolved from the vendored docs (docs/snapend/networking/intra-snapend.mdx). Every snap in the snapend gets two internal URLs, injected into the BYOSnap environment as env vars: `SNAPEND_<SNAP_NAME>_HTTP_URL` (e.g. `http://service-inventory:8090/` — HTTP port is always 8090) and `SNAPEND_<SNAP_NAME>_GRPC_URL` (e.g. `service-inventory:8080` — gRPC port is always 8080). Hosts follow the `service-<snap>` convention and are reachable only inside the snapend network, so for Auth the gRPC address comes from `SNAPEND_AUTH_GRPC_URL` (`service-auth:8080`). BYOSnap-to-snap is documented as the most common route, with Snapser-provided protos as the official gRPC path (the same protos compiled into snapser-pb/). One residual detail to confirm during implementation: the documented internal-call example is HTTP and passes `SNAPEND_INTERNAL_HEADER` as the gateway header; whether gRPC calls need that value attached as call metadata is not shown — verify when wiring the auth client._

## References
_None._

## Child pages
- [Implementation plan — Meta-Game BYOSnap — Go service scaffold](implementation-plan:mq8ejxt1-005w-iw8mhf)
- [Testing plan — Meta-Game BYOSnap — Go service scaffold](testing-plan:mq8ejxt1-005x-8qonc7)
- [Spec — Meta-Game BYOSnap — Go service scaffold](feature-spec:mq8ejxt1-005y-pgw5j3)

## Commits
_None._
