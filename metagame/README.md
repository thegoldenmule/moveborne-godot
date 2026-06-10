# byosnap-metagame

The meta-game service scaffold (see the *Meta-Game BYOSnap — Go service scaffold* feature brief
in the wiki). A Go BYOSnap that proves the two connectivity paths and nothing else — no
meta-game features (quests, economy, offers) live here yet:

1. **client → gateway → service** — `GET {base}/ping` echoes the gateway-stamped `User-Id`
   header (401 without it).
2. **service → snap (internal auth)** — `GET {base}/snap-check` makes one read-only
   `auth.AuthService/GetUser` gRPC round trip against the Auth snap using the vendored stubs
   in `../snapser-pb`.

`GET /health` answers both unprefixed (platform readiness probe) and under the base path.

## Endpoints

| Route | Auth | Response |
|---|---|---|
| `GET /health`, `GET {base}/health` | none | `{"status":"ok"}` |
| `GET {base}/ping` | gateway session (`User-Id`) | `{"ok":true,"userId":...,"version":...}` |
| `GET {base}/snap-check` | gateway session (`User-Id`) | `{"snap":"auth","rpc":...,"durationMs":...,"upstream":"OK"}` — 502 with the upstream gRPC status text on failure |

`{base}` is `BYOSNAP_BASE_PATH` (deployed: `/v1/byosnap-metagame`). The gateway forwards the
full prefix without stripping it, mirroring the validator's contract.

## Configuration (env only)

| Var | Meaning |
|---|---|
| `PORT` | listen port, default `8080` |
| `BYOSNAP_BASE_PATH` | unstripped gateway prefix; empty ⇒ unprefixed routes only |
| `SNAPEND_AUTH_GRPC_URL` | Auth snap internal gRPC address (platform-injected, `service-auth:8080`); unset ⇒ snap-check reports `unconfigured` |
| `SNAPEND_INTERNAL_HEADER` | internal-auth value (platform-injected); attached to snap calls as `gateway` gRPC metadata |

## Local loop

```bash
cd metagame
go build ./... && go vet ./...
PORT=18080 BYOSNAP_BASE_PATH=/v1/byosnap-metagame go run ./cmd/server

curl localhost:18080/health
curl -H 'User-Id: me' localhost:18080/v1/byosnap-metagame/ping
curl -H 'User-Id: me' localhost:18080/v1/byosnap-metagame/snap-check   # 502 unconfigured locally
```

There is no local gateway, so callers self-stamp `User-Id` (same pattern as the validator).

## Container loop

The build context MUST be the repo root so both `metagame/` and `snapser-pb/` are visible
(the root `.dockerignore` allowlists exactly those two directories):

```bash
docker build -f metagame/Dockerfile --platform linux/arm64 -t byosnap-metagame:dev .
docker run --rm -p 18081:8080 -e BYOSNAP_BASE_PATH=/v1/byosnap-metagame byosnap-metagame:dev
```

## Deploy loop (Snapser app c4n1awfs)

`snapctl byosnap sync` publishes the image and updates the dev snapend in one blocking call.
Stage a minimal context first so snapctl never sweeps up the full repo:

```bash
CTX=/tmp/byosnap-metagame-ctx
rm -rf $CTX && mkdir -p $CTX && cp -R metagame snapser-pb $CTX/
snapctl byosnap sync --byosnap-id byosnap-metagame \
    --path $CTX --resources-path $CTX/metagame \
    --version vX.Y.Z --snapend-id c4n1awfs --blocking
```

Bump `--version` on every publish. The profile (`snapser-byosnap-profile.json`) carries the
platform contract: linux/arm64, http :8080, readiness probe on `/health`, dev sizing
0.25 vCPU / 0.25 GB / 1 replica.

### Gateway smoke

```bash
python3 .claude/skills/snapser-validator/scripts/client.py login   # anonymous session
TOKEN=$(python3 .claude/skills/snapser-validator/scripts/client.py token)
G=https://gateway.snapser.com/c4n1awfs/v1/byosnap-metagame
curl -H "Token: $TOKEN" $G/ping        # 200, your own user id echoed
curl -H "Token: $TOKEN" $G/snap-check  # 200, upstream OK
curl $G/ping                           # rejected by the gateway (no token)
```

## Consuming snapser-pb

Every generated package declares `package proto`, so import each snap's directory under a
distinct alias (`authpb "snapser-pb/auth"`, …). The module is consumed via a local `replace`
directive in `go.mod`; generated files are never edited. `snapser-pb/google/` contains a
quarantine `go.mod` because that directory mixes three Go packages and can never build — the
stubs import the canonical upstream `genproto` packages instead.
