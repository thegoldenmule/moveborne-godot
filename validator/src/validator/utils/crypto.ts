import { createHmac, randomBytes, timingSafeEqual } from "crypto";
import { canonicalStringify } from "@spyre-io/moveborne-logic";

export function generateConnectionId(): string {
  return randomBytes(32).toString("hex");
}

export function generateUUID(): string {
  return randomBytes(16).toString("hex");
}

export function computeHmacSignature(data: unknown, secret: string): string {
  const canonical = canonicalStringify(data);
  const hmac = createHmac("sha256", secret);
  hmac.update(canonical);
  return hmac.digest("hex");
}

export function verifyHmacSignature(
  data: unknown,
  signature: string,
  secret: string,
): boolean {
  const expected = computeHmacSignature(data, secret);

  if (signature.length !== expected.length) {
    return false;
  }

  const signatureBuffer = Buffer.from(signature, "hex");
  const expectedBuffer = Buffer.from(expected, "hex");

  return timingSafeEqual(signatureBuffer, expectedBuffer);
}

export function signValidatorResponse(
  match_id: string,
  index: number,
  action: unknown,
  state_hash: string,
  secret: string,
): string {
  return computeHmacSignature({ match_id, index, action, state_hash }, secret);
}

export function verifyValidatorSignature(
  match_id: string,
  index: number,
  action: unknown,
  state_hash: string,
  signature: string,
  secret: string,
): boolean {
  return verifyHmacSignature(
    { match_id, index, action, state_hash },
    signature,
    secret,
  );
}
