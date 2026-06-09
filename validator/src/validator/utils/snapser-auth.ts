/**
 * Snapser gateway trust check.
 *
 * A BYOSnap is only reachable through the Snapser gateway (private snapend
 * network — there is no direct ingress to the container). The gateway validates
 * the caller's credential against the Auth snap BEFORE forwarding, and stamps
 * the result on the forwarded request as plain headers:
 *
 *   User-Id:   <validated user id>     (set only after token validation passed)
 *   Auth-Type: user | api-key          (which credential the caller presented)
 *   Gateway:   external | internal     (internal = snap-to-snap inside the snapend)
 *
 * Snapser does not expose a signed claim / JWKS for offline verification — the
 * headers ARE the claim, trustworthy because nothing but the gateway can reach
 * this service. So "verifying the caller" means: bind the gateway-validated
 * User-Id to the player_id the request claims to act for. Trusted non-user
 * callers (api-key server code, internal snap-to-snap) carry no user context,
 * so no player binding is possible — they are accepted as-is.
 */

export type SnapserAuthResult = { ok: true } | { ok: false; reason: string };

type HeaderBag = Record<string, string | string[] | undefined>;

function header(headers: HeaderBag, name: string): string | undefined {
  const v = headers[name];
  return Array.isArray(v) ? v[0] : v;
}

/**
 * Verify a gateway-forwarded request acts for `player_id`. `headers` must have
 * lowercased keys (Hono's `c.req.header()` and Socket.IO's
 * `socket.handshake.headers` both do).
 */
export function verifySnapserCaller(headers: HeaderBag, player_id: string): SnapserAuthResult {
  const gateway = header(headers, "gateway")?.toLowerCase();
  const authType = header(headers, "auth-type")?.toLowerCase();
  if (gateway === "internal" || authType === "internal" || authType === "api-key") {
    return { ok: true };
  }
  const userId = header(headers, "user-id");
  if (!userId) {
    return { ok: false, reason: "Missing gateway-validated User-Id header" };
  }
  if (userId !== player_id) {
    return { ok: false, reason: "player_id does not match the authenticated user" };
  }
  return { ok: true };
}
