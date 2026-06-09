import { describe, expect, test } from "bun:test";
import { verifySnapserCaller } from "../utils/snapser-auth";

describe("verifySnapserCaller", () => {
  test("accepts a gateway-validated user matching player_id", () => {
    expect(
      verifySnapserCaller({ "auth-type": "user", "user-id": "u1", gateway: "external" }, "u1"),
    ).toEqual({ ok: true });
  });

  test("rejects when User-Id does not match player_id", () => {
    const r = verifySnapserCaller({ "auth-type": "user", "user-id": "u1" }, "someone-else");
    expect(r.ok).toBe(false);
  });

  test("rejects when no User-Id was forwarded", () => {
    const r = verifySnapserCaller({ "auth-type": "user" }, "u1");
    expect(r.ok).toBe(false);
  });

  test("rejects an empty header bag (direct call that bypassed the gateway)", () => {
    expect(verifySnapserCaller({}, "u1").ok).toBe(false);
  });

  test("accepts api-key callers without user binding", () => {
    expect(verifySnapserCaller({ "auth-type": "api-key" }, "any").ok).toBe(true);
  });

  test("accepts internal snap-to-snap callers", () => {
    expect(verifySnapserCaller({ gateway: "internal" }, "any").ok).toBe(true);
    expect(verifySnapserCaller({ "auth-type": "internal" }, "any").ok).toBe(true);
  });

  test("handles array-valued headers (first value wins)", () => {
    expect(verifySnapserCaller({ "user-id": ["u1", "u2"] }, "u1").ok).toBe(true);
  });

  test("a client-spoofed User-Id with no gateway cannot impersonate trusted callers", () => {
    // Gateway/Auth-Type values are case-insensitive but must be the trusted literals.
    expect(verifySnapserCaller({ gateway: "External", "user-id": "u1" }, "u2").ok).toBe(false);
  });
});
