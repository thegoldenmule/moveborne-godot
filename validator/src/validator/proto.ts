/**
 * Runtime protobuf registry. Loads the committed .proto sources (no codegen
 * step — mirrors how the logic package ships a prebuilt dist) and exposes the
 * message types both the Hermes envelope and the validator RPCs need.
 *
 * keepCase keeps snake_case field names so decoded objects line up with the
 * service's wire interfaces (and with what @grpc/proto-loader produces for
 * the gRPC transport).
 */
import protobuf from "protobufjs";
import { join } from "node:path";

export const PROTO_DIR = join(import.meta.dir, "..", "..", "protos");
export const VALIDATOR_PROTO = join(PROTO_DIR, "moveborne", "validator", "v1", "validator.proto");
export const HERMES_PROTO = join(PROTO_DIR, "hermes", "hermes_envelope.proto");

// Single owner of the service-routing fact, so the gRPC transport and the
// Hermes-emulation dispatcher cannot drift (a name registered by one but not
// the other silently breaks local-vs-deployed parity).
//
// CANONICAL_PACKAGE is the proto package. ALIAS_PACKAGES are the extra spellings
// Snapser Hermes routes a BYOSnap by: it resolves the method string's package
// segment to a snap id, so the deployed game sends "/byosnap-validator…" — the
// gRPC server registers all of these as aliases, and the emulation accepts them.
export const CANONICAL_PACKAGE = "moveborne.validator.v1";
export const ALIAS_PACKAGES = ["byosnap-validator", "byosnap_validator", "byosnapvalidator"];
export const SERVICE_NAME = "ValidatorService";
/** Full "/<package>.ValidatorService" routing names the dispatcher accepts. */
export const SERVICE_PATHS = [CANONICAL_PACKAGE, ...ALIAS_PACKAGES].map((p) => `${p}.${SERVICE_NAME}`);
/** The three RPCs, in one place — handler tables key off these. */
export const RPC_NAMES = ["InitMatch", "ValidateAction", "CompleteMatch"] as const;
export type RpcName = (typeof RPC_NAMES)[number];

export interface ProtoRegistry {
  root: protobuf.Root;
  ClientMessage: protobuf.Type;
  ServerMessage: protobuf.Type;
  /** RPC name -> [request type, response type]. */
  rpcTypes: Record<string, [protobuf.Type, protobuf.Type]>;
}

let cached: ProtoRegistry | null = null;

export function getProtoRegistry(): ProtoRegistry {
  if (cached) return cached;

  const root = new protobuf.Root();
  // Resolve imports relative to the protos directory.
  root.resolvePath = (_origin, target) => (target.startsWith("/") ? target : join(PROTO_DIR, target));
  loadSyncKeepCase(root, HERMES_PROTO);
  loadSyncKeepCase(root, VALIDATOR_PROTO);

  const v1 = "moveborne.validator.v1";
  cached = {
    root,
    ClientMessage: root.lookupType("hermes.ClientMessage"),
    ServerMessage: root.lookupType("hermes.ServerMessage"),
    rpcTypes: {
      InitMatch: [root.lookupType(`${v1}.InitMatchRequest`), root.lookupType(`${v1}.InitMatchResponse`)],
      ValidateAction: [
        root.lookupType(`${v1}.ValidateActionRequest`),
        root.lookupType(`${v1}.ValidateActionResponse`),
      ],
      CompleteMatch: [
        root.lookupType(`${v1}.CompleteMatchRequest`),
        root.lookupType(`${v1}.CompleteMatchResponse`),
      ],
    },
  };
  return cached;
}

function loadSyncKeepCase(root: protobuf.Root, file: string): void {
  // Root.loadSync accepts parse options; keepCase preserves declared names.
  root.loadSync(file, { keepCase: true });
}

/** Decode `bytes` as `type`, returning a plain object with snake_case keys. */
export function decodeMessage<T>(type: protobuf.Type, bytes: Uint8Array): T {
  const msg = type.decode(bytes);
  return type.toObject(msg, {
    longs: Number,
    enums: Number,
    bytes: Uint8Array,
    defaults: true,
  }) as T;
}

/** Encode a plain (snake_case) object as `type`. */
export function encodeMessage(type: protobuf.Type, value: Record<string, unknown>): Uint8Array {
  const err = type.verify(value);
  if (err) throw new Error(`${type.fullName} verify failed: ${err}`);
  return type.encode(type.fromObject(value)).finish();
}
