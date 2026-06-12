/**
 * S2S client for the Snapser Storage snap (the per-user story_progress
 * json-blob). Same transport selection as snaps/inventory.ts:
 *
 *   internal — inside the snapend (SNAPEND_STORAGE_HTTP_URL +
 *     SNAPEND_INTERNAL_HEADER, sent as `Gateway`).
 *   api-key — public gateway base + auth-snap api-key (`Api-Key`).
 *   disabled — neither credential (local `bun run dev`); reads return null and
 *     writes are logged no-ops so the validation pipeline is unaffected.
 *
 * The blob is written ONLY through this s2s path. The snapend's Auth snap must
 * carry a user-auth restriction on the storage WRITE routes — Storage allows
 * user-auth writes by default, and a client that can rewrite its own
 * rewarded_stars watermark could re-farm star rewards.
 */

import type { ValidatorConfig } from "../types";

/** Owner-scoped blob path segment. `protected` so the owner can read it with
 *  a plain session while writes stay s2s (enforced via auth restrictions). */
const ACCESS_TYPE = "protected";
export const STORY_PROGRESS_KEY = "story_progress";

export type StorageTransport =
  | { kind: "internal"; baseUrl: string; header: string }
  | { kind: "api-key"; baseUrl: string; apiKey: string }
  | { kind: "disabled" };

export function resolveStorageTransport(config: ValidatorConfig): StorageTransport {
  if (config.storageInternalUrl && config.internalHeader) {
    return {
      kind: "internal",
      baseUrl: config.storageInternalUrl.replace(/\/+$/, ""),
      header: config.internalHeader,
    };
  }
  if (config.snapserApiKey) {
    return {
      kind: "api-key",
      baseUrl: config.snapserGatewayUrl.replace(/\/+$/, ""),
      apiKey: config.snapserApiKey,
    };
  }
  return { kind: "disabled" };
}

type FetchLike = typeof fetch;

export class StorageClient {
  private transport: StorageTransport;
  private fetchFn: FetchLike;

  constructor(transport: StorageTransport, fetchFn: FetchLike = fetch) {
    this.transport = transport;
    this.fetchFn = fetchFn;
  }

  get enabled(): boolean {
    return this.transport.kind !== "disabled";
  }

  get transportKind(): string {
    return this.transport.kind;
  }

  private headers(): Record<string, string> {
    if (this.transport.kind === "internal") {
      return { "Content-Type": "application/json", "Gateway": this.transport.header };
    }
    if (this.transport.kind === "api-key") {
      return { "Content-Type": "application/json", "Api-Key": this.transport.apiKey };
    }
    return {};
  }

  private blobUrl(userId: string, key: string): string {
    const base = this.transport.kind === "disabled" ? "" : this.transport.baseUrl;
    return `${base}/v1/storage/owner/${encodeURIComponent(userId)}/${ACCESS_TYPE}/json-blobs/${encodeURIComponent(key)}`;
  }

  /** Read a blob's value. null when disabled, missing (404), or on failure —
   *  callers fall back to a default and must treat reads as best-effort. */
  async getJsonBlob<T>(userId: string, key: string): Promise<T | null> {
    if (this.transport.kind === "disabled") return null;
    try {
      const res = await this.fetchFn(this.blobUrl(userId, key), {
        method: "GET",
        headers: this.headers(),
      });
      if (res.status === 404) return null;
      if (!res.ok) {
        console.error(`[storage] get ${key} for ${userId} failed: HTTP ${res.status} ${await res.text()}`);
        return null;
      }
      const body = (await res.json()) as { value?: T };
      return body.value ?? null;
    } catch (error) {
      console.error(`[storage] get ${key} for ${userId} failed:`, error);
      return null;
    }
  }

  /** Replace (create-if-missing) a blob. False when disabled or on failure. */
  async putJsonBlob(userId: string, key: string, value: unknown): Promise<boolean> {
    if (this.transport.kind === "disabled") {
      console.log(`[storage] writes disabled — skipped ${key} for ${userId}`);
      return false;
    }
    try {
      const res = await this.fetchFn(this.blobUrl(userId, key), {
        method: "PUT",
        headers: this.headers(),
        body: JSON.stringify({ value, create: true }),
      });
      if (!res.ok) {
        console.error(`[storage] put ${key} for ${userId} failed: HTTP ${res.status} ${await res.text()}`);
        return false;
      }
      return true;
    } catch (error) {
      console.error(`[storage] put ${key} for ${userId} failed:`, error);
      return false;
    }
  }
}
