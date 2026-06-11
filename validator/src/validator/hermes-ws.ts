/**
 * Local-dev Hermes emulation: the validator serves the SAME protobuf
 * ClientMessage/ServerMessage envelope the Snapser Hermes WSS endpoint
 * speaks, at ws://localhost:<port>/hermes/ws?token=<player-id>. The game
 * client therefore has exactly one codepath — only the URL differs between
 * local dev and the deployed gateway.
 *
 * Identity: locally there is no gateway, so the token query param IS the
 * self-stamped player id (the same trust model as the old self-stamped
 * User-Id header). When real gateway headers are present on the upgrade
 * (deployed direct-WS callers), those win.
 */
import { GrpcStatus, ServiceError, type CallerHeaders, type ValidatorService } from "./service";
import { decodeMessage, encodeMessage, getProtoRegistry } from "./proto";

const MESSAGE_TYPE_SNAP_API_PROXY = 4;
const MESSAGE_TYPE_ERROR = 5;
const MESSAGE_TYPE_PINGPONG = 7;

/** Hermes's observed error for a method it cannot route. */
const INVALID_SERVICE_CODE = 500;

const SERVICE_NAMES = [
  "moveborne.validator.v1.ValidatorService",
  "byosnap-validator.ValidatorService", // what the game sends (Hermes routes by BYOSnap id)
  "byosnap_validator.ValidatorService",
  "byosnapvalidator.ValidatorService",
];

interface DecodedClientMessage {
  mid: string;
  message_type: number;
  ping?: object;
  snap_api_request?: { api_method: string; payload: Uint8Array };
}

export class HermesDispatcher {
  private readonly methods = new Map<
    string,
    (payload: Uint8Array, caller: CallerHeaders) => Promise<Uint8Array>
  >();

  constructor(service: ValidatorService) {
    const { rpcTypes } = getProtoRegistry();
    const impls: Record<string, (req: any, caller: CallerHeaders) => Promise<unknown>> = {
      InitMatch: (req, caller) => service.initMatch(req, caller),
      ValidateAction: (req, caller) => service.validateAction(req, caller),
      CompleteMatch: (req, caller) => service.completeMatch(req, caller),
    };
    for (const [rpc, [reqType, respType]] of Object.entries(rpcTypes)) {
      const impl = impls[rpc]!;
      const bound = async (payload: Uint8Array, caller: CallerHeaders): Promise<Uint8Array> => {
        const request = decodeMessage<any>(reqType, payload);
        const response = await impl(request, caller);
        return encodeMessage(respType, response as Record<string, unknown>);
      };
      for (const svc of SERVICE_NAMES) {
        this.methods.set(`/${svc}/${rpc}`, bound);
      }
    }
  }

  /** Handle one binary WS frame; returns the ServerMessage frame to send. */
  async handleFrame(frame: Uint8Array, caller: CallerHeaders): Promise<Uint8Array> {
    const { ClientMessage, ServerMessage } = getProtoRegistry();
    let msg: DecodedClientMessage;
    try {
      msg = decodeMessage<DecodedClientMessage>(ClientMessage, frame);
    } catch {
      return encodeMessage(ServerMessage, {
        mid: "",
        message_type: MESSAGE_TYPE_ERROR,
        timestamp: nowSeconds(),
        error: { code: 2, error_message: "malformed ClientMessage" },
      });
    }

    // Unlike live Hermes (which drops the connection on ping — clients must
    // not initiate pings), the emulation answers pong to be debug-friendly.
    if (msg.ping) {
      return encodeMessage(ServerMessage, {
        mid: msg.mid,
        message_type: MESSAGE_TYPE_PINGPONG,
        timestamp: nowSeconds(),
        pong: {},
      });
    }

    const req = msg.snap_api_request;
    if (!req?.api_method) {
      return encodeMessage(ServerMessage, {
        mid: msg.mid,
        message_type: MESSAGE_TYPE_ERROR,
        timestamp: nowSeconds(),
        error: { code: 2, error_message: "expected snap_api_request" },
      });
    }

    const handler = this.methods.get(req.api_method);
    if (!handler) {
      // Mirror the live Hermes response shape for unroutable methods.
      return encodeMessage(ServerMessage, {
        mid: msg.mid,
        message_type: MESSAGE_TYPE_ERROR,
        timestamp: nowSeconds(),
        error: { code: INVALID_SERVICE_CODE, error_message: "invalid service" },
      });
    }

    try {
      const payload = await handler(req.payload ?? new Uint8Array(), caller);
      return encodeMessage(ServerMessage, {
        mid: msg.mid,
        message_type: MESSAGE_TYPE_SNAP_API_PROXY,
        timestamp: nowSeconds(),
        api_response: {
          caller_method: req.api_method,
          caller_time: nowSeconds(),
          payload,
          is_error: false,
        },
      });
    } catch (err) {
      const code = err instanceof ServiceError ? err.code : GrpcStatus.INTERNAL;
      const message = err instanceof Error ? err.message : "internal error";
      return encodeMessage(ServerMessage, {
        mid: msg.mid,
        message_type: MESSAGE_TYPE_SNAP_API_PROXY,
        timestamp: nowSeconds(),
        api_response: {
          caller_method: req.api_method,
          caller_time: nowSeconds(),
          payload: new Uint8Array(),
          is_error: true,
          error: { code, error_message: message },
        },
      });
    }
  }
}

/** Caller identity for a WS upgrade: gateway headers win; otherwise the token
 *  query param is the self-stamped local player id. */
export function upgradeCallerHeaders(reqHeaders: Headers, url: URL): CallerHeaders {
  const caller: CallerHeaders = {};
  for (const name of ["gateway", "auth-type", "user-id", "token"]) {
    const v = reqHeaders.get(name);
    if (v) caller[name] = v;
  }
  if (!caller["user-id"]) {
    const token = url.searchParams.get("token");
    if (token) {
      caller["user-id"] = token;
      caller["auth-type"] = "user";
    }
  }
  return caller;
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}
