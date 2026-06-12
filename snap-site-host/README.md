# snap-site-host

A **generic, game-agnostic static-site host** packaged as a Snapser BYOSnap: stock nginx that
serves whatever web build you drop into [`site/`](./site). Nothing here is Moveborne-specific —
the same image hosts any static site (a Godot web export, an SPA, a landing page) for any game.

It is deliberately a separate, game-agnostic project so it can be reused across games.

> ⚠️ **It cannot publicly host a browser-loaded site behind the Snapser gateway** — the gateway
> requires an auth token on every BYOSnap route. See
> [Gateway auth: what actually happens](#gateway-auth-what-actually-happens-tested-2026-06-12).
> Use it only for token-bearing (authenticated) asset fetches; host the game's web page on
> Amplify.

## Layout

```
snap-site-host/
├── Dockerfile                       # nginx:1.27-alpine, copies ./site → web root
├── nginx/default.conf.template      # envsubst'd at start; ${BASE_PATH} + ${LISTEN_PORT}
├── sync-build.sh                    # copy a game's web build into ./site (default: ../web-dist)
├── site/                            # ← the web build lives here (EMPTY in git; payload gitignored)
├── snapser-byosnap-profile.json     # BYOSnap profile (ports, readiness, env)
└── swagger.json                     # marks routes PUBLIC (auth-passthrough) + SDK/Explorer
```

`site/` is a drop target: its committed state is empty (`.gitkeep` only), and a synced build is
gitignored so this host never carries a duplicate game build.

## How routing works

The Snapser gateway routes to a BYOSnap **by prefix** and forwards the full path **unstripped**
(e.g. a request to `…/v1/byosnap-site-host/assets/game.wasm` arrives at nginx with that exact
path). So the nginx config aliases the whole base path onto the web root — you do **not** enumerate
individual files. `BASE_PATH` (default `/v1/byosnap-site-host`) is the single knob that changes per
snap id; override it via the profile's `env_params` if you publish under a different id.

## Use it for a game

1. Sync the game's web build into `site/`:
   ```bash
   ./sync-build.sh                 # defaults to ../web-dist (this repo's Moveborne web build)
   ./sync-build.sh /path/to/build  # any other game's web export dir
   ```
2. Build/run locally to sanity-check:
   ```bash
   docker build -t site-host .
   docker run --rm -p 8080:8080 site-host
   # build at  http://localhost:8080/v1/byosnap-site-host/
   # probe at  http://localhost:8080/health
   ```
3. Publish + deploy via `snapctl` (same loop as `validator/`): `byosnap publish` with
   `--byosnap-profile snapser-byosnap-profile.json`, then add it to a snapend.

> **`language: "node"`** in the profile is required metadata used only for SDK generation; it has
> no effect on a static host (no SDK is generated). The value is cosmetic.

### Headers / compression notes

Verified against this repo's Godot web export (`web-dist/`):

- **No COOP/COEP needed.** The export is built **without threads** (`thread_support=false`,
  `GODOT_THREADS_ENABLED = false`), so it needs no `SharedArrayBuffer` / cross-origin isolation.
  Those headers stay commented out in the nginx template — matching what Amplify ships.
- **Brotli is client-side.** `.wasm`/`.pck` ship as `.br` blobs that `mb_brotli_boot.js`
  decompresses in JS (no `Content-Encoding`), so nginx serves them as opaque `application/octet-stream` —
  no `ngx_brotli` module required.
- **Cache headers mirror `customHttp.yml`**: `index.html` → `no-store`; stable un-hashed
  engine/code assets (`.js`, `.wasm`, `.br`) → `max-age=0, must-revalidate` (+ nginx ETag → 304s);
  images → `max-age=86400`. `.wasm` is served as `application/wasm` (stock nginx ≥1.21.1).

## Gateway auth: what actually happens (TESTED 2026-06-12)

**This host cannot serve a browser-loaded site publicly.** Verified empirically by publishing
`byosnap-site-host v0.0.1` and deploying it to a real snapend (`c8nhlbzp`):

| Request | Result |
|---|---|
| `GET …/v1/byosnap-site-host/` **no token** | `400 "Session token not found"` (gateway, never reaches nginx) |
| nested `…/index.wasm.br` **no token** | `400` (same — even nested) |
| `…/?token=<jwt>` (query param) | `400` (gateway ignores token-in-query for HTTP) |
| `GET …/v1/byosnap-site-host/` **with `Token:` header** | **`200`**, `index.html` 5486 B |
| nested `…/index.wasm.br` **with `Token:` header** | **`200`**, 6485841 B (byte-exact) |

Three findings that kill the public-hosting idea:

1. **`x-snapser-auth-passthrough: true` does NOT make a BYOSnap route public.** The gateway demands
   a token on *every* BYOSnap route regardless. (Confirmed against the validator too — its own
   passthrough-tagged routes also 400 tokenless; it only works in prod because it's reached over
   the Hermes WS with `?token=`.) The extension affects SDK/Explorer grouping, not gateway auth.
2. **Auth is mandatory in every snapend.** `snapend create` and `apply` both reject a manifest
   without the `auth` service (`"Cluster manifest must include auth service"`), so the
   "no-Auth-snap → no gateway checks" path in the (outdated) security doc isn't reachable.
3. **A cold browser navigation can't carry a token** (no custom headers on a top-level GET, and
   `?token=` is rejected), so the gateway 400s before nginx ever runs.

**What this host IS still good for:** serving static assets to an **already-authenticated client
that can attach the `Token:` header** in code (e.g. an in-game CDN-style asset fetch) — not as the
host for the game's web page itself. For the browser-loaded web build, host it **outside** the
Snapser gateway (AWS Amplify, as today).

### Reproduce the test

```bash
G=https://gateway.snapser.com/<snapend-id>
curl -s -o /dev/null -w "%{http_code}\n" "$G/v1/byosnap-site-host/"                 # 400 (no token)
T=$(curl -s -X PUT "$G/v1/auth/login/anon" -H 'Content-Type: application/json' \
      -d '{"username":"t","create_user":true}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["user"]["session_token"])')
curl -s -o /dev/null -w "%{http_code}\n" -H "Token: $T" "$G/v1/byosnap-site-host/"  # 200 (with token)
```
