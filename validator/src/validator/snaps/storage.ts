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

  /** Read a blob. A MISSING blob (404) is ok with value=null — distinct from a
   *  FAILED read ({ok:false}): callers must never treat a transient failure as
   *  "no data yet" (merging against an empty default would wipe real progress
   *  and reset the reward watermarks on the next write). `cas` is the
   *  concurrency token for putJsonBlob. */
  async readJsonBlob<T>(
    userId: string,
    key: string,
  ): Promise<{ ok: true; value: T | null; cas: string } | { ok: false }> {
    if (this.transport.kind === "disabled") return { ok: false };
    try {
      const res = await this.fetchFn(this.blobUrl(userId, key), {
        method: "GET",
        headers: this.headers(),
      });
      if (res.status === 404) return { ok: true, value: null, cas: "" };
      if (!res.ok) {
        console.error(`[storage] get ${key} for ${userId} failed: HTTP ${res.status} ${await res.text()}`);
        return { ok: false };
      }
      const body = (await res.json()) as { value?: T; cas?: string };
      return { ok: true, value: body.value ?? null, cas: body.cas ?? "" };
    } catch (error) {
      console.error(`[storage] get ${key} for ${userId} failed:`, error);
      return { ok: false };
    }
  }

  /** Replace a blob, guarded by the cas token from the paired read ("" =
   *  create-if-missing). A concurrent writer invalidates the cas and the PUT
   *  fails — the caller withholds rewards rather than double-minting from a
   *  stale watermark. False when disabled or on any failure. */
  async putJsonBlob(userId: string, key: string, value: unknown, cas: string): Promise<boolean> {
    if (this.transport.kind === "disabled") {
      console.log(`[storage] writes disabled — skipped ${key} for ${userId}`);
      return false;
    }
    try {
      const body: Record<string, unknown> = cas === "" ? { value, create: true } : { value, cas };
      const res = await this.fetchFn(this.blobUrl(userId, key), {
        method: "PUT",
        headers: this.headers(),
        body: JSON.stringify(body),
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
