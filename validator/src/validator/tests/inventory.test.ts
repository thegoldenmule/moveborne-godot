import { describe, expect, test } from "bun:test";
import { InventoryClient, resolveInventoryTransport } from "../snaps/inventory";
import type { ValidatorConfig } from "../types";

const baseConfig: ValidatorConfig = {
  sharedSecret: "x",
  matchSessionTTL: 3600,
  port: 5555,
  grpcPort: 8081,
  snapserGatewayUrl: "https://gateway.snapser.com/c4n1awfs",
};

type RecordedCall = { url: string; init: RequestInit };

function mockFetch(status: number, body: unknown, calls: RecordedCall[]): typeof fetch {
  return (async (url: any, init?: any) => {
    calls.push({ url: String(url), init: init ?? {} });
    return new Response(JSON.stringify(body), { status });
  }) as typeof fetch;
}

describe("resolveInventoryTransport", () => {
  test("prefers the platform-injected internal route", () => {
    const t = resolveInventoryTransport({
      ...baseConfig,
      inventoryInternalUrl: "http://service-inventory:8090/",
      internalHeader: "secret-internal",
      snapserApiKey: "also-set",
    });
    expect(t).toEqual({ kind: "internal", baseUrl: "http://service-inventory:8090", header: "secret-internal" });
  });

  test("falls back to gateway api-key", () => {
    const t = resolveInventoryTransport({ ...baseConfig, snapserApiKey: "key-123" });
    expect(t).toEqual({ kind: "api-key", baseUrl: "https://gateway.snapser.com/c4n1awfs", apiKey: "key-123" });
  });

  test("disabled when no credentials", () => {
    expect(resolveInventoryTransport(baseConfig)).toEqual({ kind: "disabled" });
  });
});

describe("InventoryClient.incrementUserCurrency", () => {
  test("PUTs {delta_64} with Api-Key header to the gateway path and parses balances", async () => {
    const calls: RecordedCall[] = [];
    const client = new InventoryClient(
      { kind: "api-key", baseUrl: "https://gateway.snapser.com/c4n1awfs", apiKey: "key-123" },
      mockFetch(200, { previous_balance_64: "10", current_balance_64: "160" }, calls),
    );
    const result = await client.incrementUserCurrency("user-1", "coins", "150");
    expect(result).toEqual({ previous_balance_64: "10", current_balance_64: "160" });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.url).toBe("https://gateway.snapser.com/c4n1awfs/v1/inventory/users/user-1/currencies/coins");
    expect(calls[0]!.init.method).toBe("PUT");
    expect(JSON.parse(String(calls[0]!.init.body))).toEqual({ delta_64: "150" });
    expect((calls[0]!.init.headers as Record<string, string>)["Api-Key"]).toBe("key-123");
  });

  test("internal transport sends the Gateway header", async () => {
    const calls: RecordedCall[] = [];
    const client = new InventoryClient(
      { kind: "internal", baseUrl: "http://service-inventory:8090", header: "internal-secret" },
      mockFetch(200, { previous_balance_64: "0", current_balance_64: "1" }, calls),
    );
    await client.incrementUserCurrency("user-2", "souls", "1");
    expect(calls[0]!.url).toBe("http://service-inventory:8090/v1/inventory/users/user-2/currencies/souls");
    expect((calls[0]!.init.headers as Record<string, string>)["Gateway"]).toBe("internal-secret");
  });

  test("non-2xx resolves to null instead of throwing into the pipeline", async () => {
    const calls: RecordedCall[] = [];
    const client = new InventoryClient(
      { kind: "api-key", baseUrl: "https://gw", apiKey: "k" },
      mockFetch(403, { error: "forbidden" }, calls),
    );
    expect(await client.incrementUserCurrency("user-3", "coins", "5")).toBeNull();
  });

  test("disabled transport is a no-op returning null without calling fetch", async () => {
    const calls: RecordedCall[] = [];
    const client = new InventoryClient({ kind: "disabled" }, mockFetch(200, {}, calls));
    expect(await client.incrementUserCurrency("user-4", "gems", "1")).toBeNull();
    expect(calls).toHaveLength(0);
  });
});

describe("InventoryClient.getUserCurrencies", () => {
  test("parses currencies_64", async () => {
    const calls: RecordedCall[] = [];
    const client = new InventoryClient(
      { kind: "api-key", baseUrl: "https://gw", apiKey: "k" },
      mockFetch(200, { currencies_64: { coins: "150", souls: "3" } }, calls),
    );
    expect(await client.getUserCurrencies("user-5")).toEqual({ coins: "150", souls: "3" });
    expect(calls[0]!.url).toBe("https://gw/v1/inventory/users/user-5/currencies");
  });
});
