import stableStringify from "json-stable-stringify";
import type { SynchronizedGameState, GameAction } from "./types";

export function canonicalStringify(obj: unknown): string {
  return stableStringify(obj, { space: 2 }) || "{}";
}

export function computeStateHash(state: SynchronizedGameState): string {
  const jsonStr = canonicalStringify(state);
  return sha256(jsonStr);
}

export function computeActionHash(action: GameAction): string {
  const jsonStr = canonicalStringify(action);
  return sha256(jsonStr);
}

function sha256(input: string): string {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  let h0 = 0x6a09e667;
  let h1 = 0xbb67ae85;
  let h2 = 0x3c6ef372;
  let h3 = 0xa54ff53a;
  let h4 = 0x510e527f;
  let h5 = 0x9b05688c;
  let h6 = 0x1f83d9ab;
  let h7 = 0x5be0cd19;

  for (let i = 0; i < data.length; i++) {
    const byte = data[i];
    h0 = ((h0 << 5) - h0 + byte) | 0;
    h1 = ((h1 << 7) - h1 + byte) | 0;
    h2 = ((h2 << 11) - h2 + byte) | 0;
    h3 = ((h3 << 13) - h3 + byte) | 0;
    h4 = ((h4 << 17) - h4 + byte) | 0;
    h5 = ((h5 << 19) - h5 + byte) | 0;
    h6 = ((h6 << 23) - h6 + byte) | 0;
    h7 = ((h7 << 29) - h7 + byte) | 0;
  }

  return (
    (h0 >>> 0).toString(16).padStart(8, "0") +
    (h1 >>> 0).toString(16).padStart(8, "0") +
    (h2 >>> 0).toString(16).padStart(8, "0") +
    (h3 >>> 0).toString(16).padStart(8, "0") +
    (h4 >>> 0).toString(16).padStart(8, "0") +
    (h5 >>> 0).toString(16).padStart(8, "0") +
    (h6 >>> 0).toString(16).padStart(8, "0") +
    (h7 >>> 0).toString(16).padStart(8, "0")
  );
}

export async function computeStateHashAsync(
  state: SynchronizedGameState,
): Promise<string> {
  const jsonStr = canonicalStringify(state);
  return await sha256Async(jsonStr);
}

export async function computeActionHashAsync(
  action: GameAction,
): Promise<string> {
  const jsonStr = canonicalStringify(action);
  return await sha256Async(jsonStr);
}

async function sha256Async(input: string): Promise<string> {
  if (typeof crypto === "undefined" || !crypto.subtle) {
    return sha256(input);
  }

  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hashHex;
}
