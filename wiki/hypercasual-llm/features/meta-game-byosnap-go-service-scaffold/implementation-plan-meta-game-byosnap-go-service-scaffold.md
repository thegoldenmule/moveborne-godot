# Implementation plan — Meta-Game BYOSnap — Go service scaffold

**Status:** ready

## Steps
- [x] Add a minimal go.mod to the snapser-pb directory (module snapser-pb) and prove the vendored generated packages compile untouched with go build on every package.
- [x] Scaffold the metagame module: go.mod with a local replace for snapser-pb, cmd/server/main.go, internal packages for config (port, base path, internal-auth header from env) and HTTP handlers; serve /health (prefixed and unprefixed) and {base}/ping returning the gateway-stamped User-Id, 401 when the header is absent.
- [x] Local proof of path one: run the server with a self-stamped User-Id header (validator tooling pattern) and verify health and ping by curl.
- [x] Wire snap addresses from the platform-injected internal URL env vars (per the intra-snapend networking docs: each snap gets an HTTP URL on port 8090 and a gRPC URL on port 8080, host service-<snap> — the Auth gRPC address arrives in the per-snap env var, no hardcoding). Confirm whether internal gRPC requires the internal-auth header value as call metadata, mirroring the documented HTTP example; if internal gRPC is blocked, fall back to the internal HTTP surface on 8090 with endpoint contracts unchanged.
- [x] Wire the Auth snap client from the snapser-pb auth package (aliased import) behind {base}/snap-check: one read-only RPC with internal auth, JSON envelope with snap, RPC name, round-trip duration and upstream status; 502 with gRPC status text on failure.
- [x] Write the multi-stage Dockerfile (build context at repo root so metagame and snapser-pb are both visible; static linux/arm64 binary; scratch or distroless runtime) and snapser-byosnap-profile.json mirroring the validator: http 8080, readiness probe on /health, dev sizing 0.25 vCPU / 0.25 GB / 1 replica.
- [x] Container smoke locally: docker build and run, health and ping respond from inside the container image.
- [ ] Deploy to Snapser: snapctl publish the image as byosnap-metagame under app c4n1awfs, then update the snapend to attach it alongside byosnap-validator.
- [ ] Gateway smoke verification: anonymous login via the snapser-validator skill pattern, GET ping with the session token expecting our own user id back, GET snap-check expecting a successful Auth snap round trip; confirm the readiness probe is green in the portal.
- [x] Write a short metagame README covering the local run loop and the deploy loop, and record the commits on the feature brief.

## Data models & interfaces
```go
// Endpoint contracts (the only public surface of this feature).

// GET /health and GET {base}/health -> 200
type HealthResponse struct {
    Status string `json:"status"` // "ok"
}

// GET {base}/ping -> 200 (or 401 when the gateway User-Id header is absent)
type PingResponse struct {
    OK      bool   `json:"ok"`
    UserID  string `json:"userId"`  // echoed gateway-stamped User-Id header
    Version string `json:"version"` // service build version
}

// GET {base}/snap-check -> 200 (or 502 with upstream gRPC status text)
type SnapCheckResponse struct {
    Snap       string `json:"snap"`       // "auth"
    RPC        string `json:"rpc"`        // fully-qualified method invoked
    DurationMS int64  `json:"durationMs"` // round-trip time
    Upstream   string `json:"upstream"`   // upstream status, "OK" on success
}

// Config: everything from env, no files.
type Config struct {
    Port           string // PORT, default 8080
    BasePath       string // BYOSNAP_BASE_PATH, e.g. /v1/byosnap-metagame
    InternalHeader string // SNAPEND_INTERNAL_HEADER value for Gateway: internal
    AuthSnapAddr   string // internal gRPC address of the Auth snap (resolved in step 4)
}
```

## Open questions
_None._

## Resolved questions
_None._

## References
_None._

## Child pages
_None._
