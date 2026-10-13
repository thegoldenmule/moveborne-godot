# Deploying the Validator (BYOSnap)

**Status:** current

## Kind
service

## Summary
How the validator BYOSnap is shipped to Snapser: bump the version, regenerate swagger, `snapctl byosnap publish` the linux/arm64 image, `snapctl byosnap sync` it onto the dev snapend `c4n1awfs`, verify live, then refresh the committed snapend manifest. The deployed container carries no bundled story catalog — it pulls the catalog from Remote Config at runtime — so a deploy is only safe once live Remote Config `app-config/v1` already holds the catalog the new code expects.

## Purpose
The validator runs as a containerized Snapser BYOSnap behind the gateway (HTTP `:8080` external, gRPC `:8081` internal) on app/snapend `c4n1awfs`. Shipping it is a fixed publish → sync → manifest-refresh loop with a handful of non-obvious footguns: Snapser requires a fresh semver per publish; `sync` needs the profile path and rebuilds; the swagger version is derived from `package.json`; and the runtime story catalog lives in Remote Config, not the image. This page is the runbook so the loop need not be reconstructed from scattered implementation plans each time.

## Design notes
```bash
# from repo root, Docker running, snapctl authed (app c4n1awfs)
# 1. bump version in validator/src/validator/package.json, then:
( cd validator && bun run gen:swagger )

# 2. publish a fresh semver, then sync it onto the dev snapend:
snapctl byosnap publish --byosnap-id byosnap-validator --path validator --version vX.Y.Z
snapctl byosnap sync    --byosnap-id byosnap-validator --snapend-id c4n1awfs --version vX.Y.Z --path validator --blocking

# 3. verify (auth required) + refresh the committed manifest:
python3 .claude/skills/snapser-validator/scripts/client.py call GET /api/status
snapctl snapend download --snapend-id c4n1awfs --category snapend-manifest --format json --out-path "$PWD/snapser"
```

Publish is per-version immutable: Snapser will not overwrite an existing vX.Y.Z. Every deploy needs a fresh semver, which is why the package.json bump is step one.

sync rebuilds the image and requires --path (to re-import the BYOSnap profile). --skip-build is a trap here: it retags a local image that the ephemeral publish build never left on the host, so it fails with 'No such image'. Let sync rebuild.

The swagger version is generated from src/validator/package.json by gen:swagger and uploaded during publish. If you bump the image version but forget to regenerate + re-publish swagger, the API Explorer and the gateway's per-route auth keep showing the stale spec.

The deployed container has no story catalog inside it (content/story_catalog.json is .dockerignored). It pulls the catalog from the Remote Config snap at boot and serves last-known-good on a refresh failure, with NO committed-file fallback in deployed mode. Populate and verify live Remote Config app-config/v1 before syncing, or deployed story matches fail their init handshake (catalog_version_mismatch) or find no catalog at all.

Remote Config has no write API — publishing is a manual console paste of the WHOLE app-config document built by the generic driver from content/app_config.manifest.json: `bun run appconfig:emit` prints it (every registered key at once, so a paste can never drop a sibling), `bun run appconfig:verify` confirms the live config matches per key. The two old per-feature scripts (story-appconfig.ts, daily-missions-appconfig.ts) were replaced by tools/appconfig.ts + the manifest; the Godot Remote Config editor tool wraps the same emit/verify.

Side effect for clients: a byosnap sync (and any snapend apply) invalidates existing Snapser sessions server-side. Anon tokens have a ~30-day local TTL, so a client that only checks local expiry reuses a dead token after a deploy -> HTTP 401 on gateway reads and a rejected validator WS handshake. The client mitigates by re-authenticating on a 401 (MbSnapserAuth.reauth, same username -> same user + progress); the first re-auth heals the shared session for all clients. See the Snapend Provisioning (snapctl IaC) node.

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- `validator/snapser-byosnap-profile.json`
- `validator/Dockerfile`
- `validator/swagger.json`
- constant `version` in `validator/src/validator/package.json`
- `.claude/skills/snapser-validator/scripts/client.py`
- `snapser/snapend-manifest.json`
- file `generic Remote Config driver (emit|verify|status) + content/app_config.manifest.json` in `validator/src/validator/tools/appconfig.ts`

## Data model
Deploy coordinates (from `validator/snapser-byosnap-profile.json`):

| Thing | Value |
|---|---|
| BYOSnap id | `byosnap-validator` |
| Snapser app / dev snapend | `c4n1awfs` |
| External port (HTTP) | `8080` |
| Internal port (gRPC) | `8081` |
| Base path | `/v1/byosnap-validator` (gateway forwards the full prefix, unstripped) |
| Platform | `linux/arm64` |
| Version source of truth | `validator/src/validator/package.json` → drives `swagger.json` via `bun run gen:swagger` |
| Committed manifest | `snapser/snapend-manifest.json` |

Runtime story catalog is served from the Remote Config snap (`app-config/v1`, key `story_catalog`), pinned per match; the image's `content/story_catalog.json` is `.dockerignore`d. Publishing is a manual console paste of the WHOLE app-config document (every key — `story_catalog`, `daily_missions`, …, built from `content/app_config.manifest.json`): `bun run appconfig:emit` prints the full document, `bun run appconfig:verify [key]` deep-compares live vs committed per key, `bun run appconfig:status` reports each block's version across committed / live.

## Usage
Run from the repo root with Docker running and `snapctl` authenticated (Snapser app/snapend `c4n1awfs`).

**1. Pre-flight.** From `validator/`: `bun run type-check`, and from `validator/src/validator/`: `bun test` — both green. Then confirm the new code's runtime dependency is satisfied: from `validator/`, `bun run appconfig:status` (the generic Remote Config driver) must show live Remote Config `app-config/v1` matching the committed `story_catalog` block (the container has no bundled catalog — see invariants).

**2. Bump the version.** Snapser refuses to re-publish an existing version, so pick a fresh `vX.Y.Z`. Edit `version` in `validator/src/validator/package.json`, then regenerate the OpenAPI spec (its version is read from package.json): `bun run gen:swagger` from `validator/`. Commit the bump + regenerated `swagger.json`.

**3. Publish the image.** `snapctl byosnap publish --byosnap-id byosnap-validator --path validator --version vX.Y.Z`. Builds the linux/arm64 image (build context = `validator/` so the `workspace:*` logic link resolves), pushes it, and uploads `swagger.json` + `README.md`. Takes a few minutes.

**4. Sync onto the snapend.** `snapctl byosnap sync --byosnap-id byosnap-validator --snapend-id c4n1awfs --version vX.Y.Z --path validator --blocking`. `--path` is required (sync re-imports the profile) and sync rebuilds — do **not** pass `--skip-build`, which looks for a local image tag the publish step never left behind. `--blocking` waits until the snapend returns to **Live**.

**5. Verify live.** The `/api/status` route rejects unauthenticated probes (HTTP 400), so go through the gateway with a session token: `python3 .claude/skills/snapser-validator/scripts/client.py call GET /api/status`. Expect the new `version`, `transport: grpc+hermes`, and the expected `story_catalog_version` / `story_catalog_source: internal`.

**6. Refresh the committed manifest.** `snapctl snapend download --snapend-id c4n1awfs --category snapend-manifest --format json --out-path <repo>/snapser` writes `snapser/snapser-c4n1awfs-manifest.json`; move it over the tracked `snapser/snapend-manifest.json` and commit. The `byosnap-validator` version pin in the manifest should now read the new version.

## Invariants & constraints
- Build context and --path must be `validator/` (not the repo root, not `validator/src/validator`) so the `workspace:*` logic dependency link resolves at image build time.
- Every publish uses a fresh `vX.Y.Z`; existing versions are immutable. The version is bumped in `validator/src/validator/package.json` and flows into `swagger.json` via `bun run gen:swagger`.
- The deployed external port (8080) and the declared internal gRPC port (8081) are fixed; do not change the deployed external port — Hermes routes the BYOSnap by its declared internal gRPC port.
- Deployed mode has no committed-file catalog fallback: the validator serves the story catalog from Remote Config. Live `app-config/v1` must match the committed catalog before a sync goes Live.
- `snapctl byosnap sync` targets DEVELOPMENT snapends only; `c4n1awfs` is the dev snapend.

## Synced commit
159ac4e
