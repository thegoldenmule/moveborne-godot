# Testing plan — Meta-Game BYOSnap — Go service scaffold

**Status:** ready

## Planned
- Vendored stubs compile: go build succeeds across every snapser-pb package with the new go.mod and zero edits to generated files.
- Local health: GET /health returns 200 both unprefixed and under the base path.
- Local ping happy path: GET {base}/ping with a self-stamped User-Id header returns 200 with that exact user id echoed.
- Local ping rejection: GET {base}/ping without a User-Id header returns 401.
- Container parity: the same health and ping checks pass against the built linux/arm64 image running locally.
- Deployed readiness: after snapctl publish and snapend update, the byosnap-metagame readiness probe shows green in the Snapser portal and stays green.
- Gateway path proof: anonymous login, then GET ping through the gateway with the session token returns 200 and the logged-in user id — client to gateway to service confirmed.
- Gateway auth enforcement: GET ping through the gateway without a session token is rejected before reaching the service.
- Snap path proof: GET snap-check through the gateway returns 200 with upstream OK and a plausible round-trip duration — service to Auth snap confirmed.
- Snap path diagnosability: with the Auth snap address misconfigured (local only), snap-check returns 502 carrying the gRPC status text.
- Validator regression: the existing byosnap-validator health and Story-mode validation flow still pass after the snapend update.

## Passed
_None._

## Failed
_None._

## References
_None._

## Child pages
_None._
