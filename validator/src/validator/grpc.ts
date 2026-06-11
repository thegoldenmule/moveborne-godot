/**
 * gRPC transport for the validator service. This is what Snapser Hermes
 * proxies MESSAGE_TYPE_SNAP_API_PROXY calls to inside the snapend.
 *
 * Hermes resolves the method string's package segment against the snapend's
 * service registry (live-verified: "/auth.AuthService/..." routes to the auth
 * snap; unknown packages answer "invalid service"). Which package name a
 * BYOSnap registers under is not documented, so the canonical service is
 * additionally aliased under the BYOSnap-id-shaped names — registering an
 * alias is just the same handlers bound to a rewritten path.
 */
import * as grpc from "@grpc/grpc-js";
import * as loader from "@grpc/proto-loader";
import { ServiceError, rpcHandlers, type CallerHeaders, type ValidatorService as Service } from "./service";
import { ALIAS_PACKAGES, CANONICAL_PACKAGE, PROTO_DIR, VALIDATOR_PROTO } from "./proto";

function metadataToHeaders(metadata: grpc.Metadata): CallerHeaders {
  const headers: CallerHeaders = {};
  for (const [key, value] of Object.entries(metadata.getMap())) {
    headers[key] = typeof value === "string" ? value : value.toString();
  }
  return headers;
}

export function startGrpcServer(service: Service, port: number): Promise<grpc.Server> {
  const def = loader.loadSync(VALIDATOR_PROTO, {
    keepCase: true,
    longs: Number,
    enums: String,
    defaults: true,
    includeDirs: [PROTO_DIR],
  });
  const pkg = grpc.loadPackageDefinition(def) as any;
  const serviceDef: grpc.ServiceDefinition = pkg.moveborne.validator.v1.ValidatorService.service;

  const handlers = rpcHandlers(service);

  const implementation: grpc.UntypedServiceImplementation = {};
  for (const name of Object.keys(handlers) as (keyof typeof handlers)[]) {
    implementation[name] = (
      call: grpc.ServerUnaryCall<any, any>,
      callback: grpc.sendUnaryData<any>,
    ) => {
      handlers[name](call.request, metadataToHeaders(call.metadata))
        .then((resp) => callback(null, resp))
        .catch((err) => {
          const code = err instanceof ServiceError ? err.code : grpc.status.INTERNAL;
          callback({ code, message: err?.message ?? "internal error" } as grpc.ServiceError, null);
        });
    };
  }

  const server = new grpc.Server();
  server.addService(serviceDef, implementation);
  for (const alias of ALIAS_PACKAGES) {
    server.addService(aliasServiceDef(serviceDef, alias), implementation);
  }

  return new Promise((resolve, reject) => {
    server.bindAsync(`0.0.0.0:${port}`, grpc.ServerCredentials.createInsecure(), (err, boundPort) => {
      if (err) return reject(err);
      console.log(`🔌 gRPC ValidatorService on :${boundPort} (${CANONICAL_PACKAGE} + aliases ${ALIAS_PACKAGES.join(", ")})`);
      resolve(server);
    });
  });
}

/** Same methods re-rooted under `<aliasPackage>.ValidatorService`. */
function aliasServiceDef(def: grpc.ServiceDefinition, aliasPackage: string): grpc.ServiceDefinition {
  const out: Record<string, grpc.MethodDefinition<unknown, unknown>> = {};
  for (const [name, method] of Object.entries(def)) {
    out[name] = {
      ...method,
      path: method.path.replace(`/${CANONICAL_PACKAGE}.`, `/${aliasPackage}.`),
    };
  }
  return out as grpc.ServiceDefinition;
}
