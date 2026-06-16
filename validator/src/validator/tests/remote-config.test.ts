import { describe, it, expect } from "bun:test";
import { resolveRemoteConfigTransport, RemoteConfigClient } from "../snaps/remote-config";
import type { ValidatorConfig } from "../types";

const base: ValidatorConfig = {
  sharedSecret: "s",
  matchSessionTTL: 1,
  port: 0,
  grpcPort: 0,
  snapserGatewayUrl: "https://gw/snap",
};

describe("resolveRemoteConfigTransport", () => {
  it("internal when internal url + header are set (trailing slash stripped)", () => {
    const t = resolveRemoteConfigTransport({ ...base, remoteConfigInternalUrl: "http://rc/", internalHeader: "hdr" });
    expect(t).toEqual({ kind: "internal", baseUrl: "http://rc", header: "hdr" });
  });

  it("api-key when only the api key is set", () => {
    const t = resolveRemoteConfigTransport({ ...base, snapserApiKey: "k" });
    expect(t).toEqual({ kind: "api-key", baseUrl: "https://gw/snap", apiKey: "k" });
  });

  it("disabled when neither credential is present", () => {
    expect(resolveRemoteConfigTransport(base)).toEqual({ kind: "disabled" });
  });
});

describe("RemoteConfigClient.fetchStoryCatalog", () => {
  const cat = { catalog_version: 1 };

  it("returns story_catalog and sends the Gateway header (internal)", async () => {
    let seen: { url: string; init: any } | undefined;
    const fetchFn = async (url: any, init: any) => {
      seen = { url: String(url), init };
      return new Response(JSON.stringify({ config: { story_catalog: cat } }), { status: 200 });
    };
    const c = new RemoteConfigClient({ kind: "internal", baseUrl: "http://rc", header: "hdr" }, fetchFn as any);
    expect(await c.fetchStoryCatalog()).toEqual(cat);
    expect(seen!.url).toBe("http://rc/v1/remote-config/app-config/v1");
    expect(seen!.init.headers["Gateway"]).toBe("hdr");
  });

  it("sends the Api-Key header (api-key transport)", async () => {
    let seen: any;
    const fetchFn = async (_url: any, init: any) => {
      seen = init;
      return new Response(JSON.stringify({ config: { story_catalog: cat } }), { status: 200 });
    };
    const c = new RemoteConfigClient({ kind: "api-key", baseUrl: "https://gw", apiKey: "k" }, fetchFn as any);
    await c.fetchStoryCatalog();
    expect(seen.headers["Api-Key"]).toBe("k");
  });

  it("returns null when the story_catalog key is absent", async () => {
    const fetchFn = async () => new Response(JSON.stringify({ config: {} }), { status: 200 });
    const c = new RemoteConfigClient({ kind: "internal", baseUrl: "http://rc", header: "h" }, fetchFn as any);
    expect(await c.fetchStoryCatalog()).toBeNull();
  });

  it("throws on a non-200 response", async () => {
    const fetchFn = async () => new Response("nope", { status: 500 });
    const c = new RemoteConfigClient({ kind: "internal", baseUrl: "http://rc", header: "h" }, fetchFn as any);
    await expect(c.fetchStoryCatalog()).rejects.toThrow();
  });

  it("returns null when disabled", async () => {
    const c = new RemoteConfigClient({ kind: "disabled" });
    expect(await c.fetchStoryCatalog()).toBeNull();
  });
});
