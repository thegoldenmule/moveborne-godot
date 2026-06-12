# ADR-21: Generate SDKs and swagger from the committed protos (godobuf, protobufjs descriptor, code-defined OpenAPI)

**Status:** accepted

## Metadata
- **Date:** 2026-06-11
- **Scope:** Validator / Client / Build & Tooling / Deployment
- **Deciders:** Benjamin Jordan

## Context
validator/protos/ is the single source of truth for the wire contract (companion ADRs), consumed by three independent toolchains: the TypeScript validator, the GDScript game client, and Snapser — which uploads validator/swagger.json on `snapctl byosnap publish` to power the API Explorer, SDK generation, and the gateway's per-route auth (x-snapser-auth-*). Each needs a binding or spec derived from the protos, and these drifted when maintained by hand: the service version lived in three places (package.json, /api/status, swagger), and swagger carried stale Socket.IO routes after the transport refactor. Additionally there is no official Godot protobuf codegen, and the validator originally parsed .proto text at runtime on every boot.

## Decision
Generate all three derived artifacts from the protos with ONE tool (tools/gen-protos.sh) and commit the outputs, so a single command regenerates everything when a .proto changes.

GDScript SDK — the vendored godobuf addon emits game/net/proto/*_pb.gd. godobuf cannot parse a `service` block, a field named `message`, or apostrophes in comments — hence the messages/service proto split and the api_method / error_message field renames (wire-safe, since field NAMES are not encoded — only numbers are).

JS SDK — protobufjs (pbjs -t json --keep-case) emits a compiled JSON descriptor (proto-gen/validator-descriptor.json) that the validator loads via protobuf.Root.fromJSON at startup, replacing the runtime .proto text parse. @grpc/proto-loader still reads validator.proto for the gRPC SERVICE definition, which the message descriptor does not carry.

swagger.json — code-defined in tools/gen-swagger.ts with the version pulled from package.json (single source of truth), regenerated and re-uploaded on deploy so Snapser picks it up. Byte-for-byte agreement between the TS encoder and the GDScript bindings is asserted by a golden-fixture verifier (verify_hermes_proto.gd against fixtures from generate-hermes-golden.ts).

## Consequences
POSITIVE: One command (tools/gen-protos.sh) regenerates every derived artifact when a proto changes; no hand-maintained bindings and no hand-edited swagger. Version drift is structurally impossible (swagger and /api/status both derive the version from package.json). The cross-language wire contract is continuously verified by the byte-parity golden, so a stale binding fails a test. Runtime startup no longer parses .proto text for message types.

NEGATIVE / COST: Adds a codegen step and a build-time dependency (protobufjs-cli) plus the vendored third-party godobuf addon (with the parsing quirks noted above). The generated outputs are committed, so they must be regenerated and reviewed when protos change — a step a contributor can forget, mitigated by the byte-parity verifier catching staleness. Snapser's swagger is HTTP-only, so the gRPC ValidatorService is documented in prose + the protos, not as OpenAPI operations.

RELATIONS: Implements the wire contract of the protobuf-contract ADR and the transport of the gRPC-over-Hermes ADR. The GDScript-generation choice is the binding half of those decisions; the swagger generator keeps the Snapser BYOSnap deploy contract (ADR-16) accurate without hand edits.

## Relations
_None._
