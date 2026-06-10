/**
 * S2S client for the Snapser Inventory snap (virtual currency).
 *
 * Two transports, auto-selected from config:
 *
 *   internal — preferred. Inside the snapend the platform injects
 *     SNAPEND_INVENTORY_HTTP_URL (http://service-inventory:8090/) and
 *     SNAPEND_INTERNAL_HEADER; internal calls hit the same REST paths with the
 *     header value sent as `Gateway`. Zero manual credentials.
 *   api-key — fallback for callers outside the snapend network: the public
 *     gateway base + an auth-snap api-key sent as `Api-Key`.
 *   disabled — neither credential present (local `bun run dev`); every call is
 *     a logged no-op so the validation pipeline is unaffected.
 *
 * Only the *_64 string fields are used (the int32 variants are deprecated and
 * would truncate). The client-facing read path (GET currencies as `user` auth)
 * stays with the game client — this service only needs increments + a balance
 * read-back for the match_rewards ack.
 */

import type {
  CurrencyName,
  GetUserCurrenciesResponse,
  IncrementUserCurrencyResponse,
  ValidatorConfig,
} from "../types";

export type InventoryTransport =
  | { kind: "internal"; baseUrl: string; header: string }
  | { kind: "api-key"; baseUrl: string; apiKey: string }
  | { kind: "disabled" };

export function resolveInventoryTransport(config: ValidatorConfig): InventoryTransport {
  if (config.inventoryInternalUrl && config.internalHeader) {
    return {
      kind: "internal",
      baseUrl: config.inventoryInternalUrl.replace(/\/+$/, ""),
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

export class InventoryClient {
  private transport: InventoryTransport;
  private fetchFn: FetchLike;

  constructor(transport: InventoryTransport, fetchFn: FetchLike = fetch) {
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

  /** Grant (or consume, negative delta) currency. Returns null when disabled
   *  or on any upstream failure — callers must treat awards as best-effort and
   *  never let a failure break validation. */
  async incrementUserCurrency(
    userId: string,
    currency: CurrencyName,
    delta64: string,
  ): Promise<IncrementUserCurrencyResponse | null> {
    if (this.transport.kind === "disabled") {
      console.log(`[inventory] awards disabled — skipped ${currency} +${delta64} for ${userId}`);
      return null;
    }
    const url = `${this.transport.baseUrl}/v1/inventory/users/${encodeURIComponent(userId)}/currencies/${encodeURIComponent(currency)}`;
    try {
      const res = await this.fetchFn(url, {
        method: "PUT",
        headers: this.headers(),
        body: JSON.stringify({ delta_64: delta64 }),
      });
      if (!res.ok) {
        console.error(`[inventory] increment ${currency} for ${userId} failed: HTTP ${res.status} ${await res.text()}`);
        return null;
      }
      return (await res.json()) as IncrementUserCurrencyResponse;
    } catch (error) {
      console.error(`[inventory] increment ${currency} for ${userId} failed:`, error);
      return null;
    }
  }

  /** Read all currency balances (currency_name -> int64-as-string). */
  async getUserCurrencies(userId: string): Promise<Record<string, string> | null> {
    if (this.transport.kind === "disabled") {
      return null;
    }
    const url = `${this.transport.baseUrl}/v1/inventory/users/${encodeURIComponent(userId)}/currencies`;
    try {
      const res = await this.fetchFn(url, { method: "GET", headers: this.headers() });
      if (!res.ok) {
        console.error(`[inventory] get currencies for ${userId} failed: HTTP ${res.status} ${await res.text()}`);
        return null;
      }
      const body = (await res.json()) as GetUserCurrenciesResponse;
      return body.currencies_64 ?? {};
    } catch (error) {
      console.error(`[inventory] get currencies for ${userId} failed:`, error);
      return null;
    }
  }
}
