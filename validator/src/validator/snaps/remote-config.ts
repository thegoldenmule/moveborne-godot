/**
 * S2S client for the Snapser Remote Config snap. The story catalog is published
 * (manually, via the console — Remote Config has no write API) to the app-config
 * document under the "story_catalog" key; the validator READS it at runtime as
 * its source of truth (see ../story/catalog.ts). Same transport selection as
 * snaps/storage.ts:
 *
 *   internal — inside the snapend (SNAPEND_REMOTE_CONFIG_HTTP_URL +
 *     SNAPEND_INTERNAL_HEADER, sent as `Gateway`).
 *   api-key — public gateway base + auth-snap api-key (`Api-Key`).
 *   disabled — neither credential (local `bun run dev`/tests); the catalog
 *     loader falls back to the committed content/story_catalog.json.
 */

import type { ValidatorConfig } from "../types";

export const APP_CONFIG_VERSION = "v1";
export const CATALOG_KEY = "story_catalog";

export type RemoteConfigTransport =
  | { kind: "internal"; baseUrl: string; header: string }
  | { kind: "api-key"; baseUrl: string; apiKey: string }
  | { kind: "disabled" };

export function resolveRemoteConfigTransport(config: ValidatorConfig): RemoteConfigTransport {
  if (config.remoteConfigInternalUrl && config.internalHeader) {
    return {
      kind: "internal",
      baseUrl: config.remoteConfigInternalUrl.replace(/\/+$/, ""),
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

export class RemoteConfigClient {
  private transport: RemoteConfigTransport;
  private fetchFn: FetchLike;

  constructor(transport: RemoteConfigTransport, fetchFn: FetchLike = fetch) {
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

  /** GET app-config v1 and return its `story_catalog` value. null when the
   *  transport is disabled or the key is absent; throws on a non-200 so the
   *  caller keeps the last-known-good rather than adopting an empty payload. */
  async fetchStoryCatalog(): Promise<unknown | null> {
    if (this.transport.kind === "disabled") return null;
    const url = `${this.transport.baseUrl}/v1/remote-config/app-config/${APP_CONFIG_VERSION}`;
    const res = await this.fetchFn(url, { method: "GET", headers: this.headers() });
    if (!res.ok) {
      throw new Error(`app-config/${APP_CONFIG_VERSION}: HTTP ${res.status} ${await res.text()}`);
    }
    const body = (await res.json()) as { config?: Record<string, unknown> };
    return body.config?.[CATALOG_KEY] ?? null;
  }
}
