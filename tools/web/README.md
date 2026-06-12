# Optimized web build → AWS Amplify

This directory holds the tooling that turns a Godot Web export into a compact,
static-host-ready bundle in `web-dist/` (committed and served as-is by AWS
Amplify).

## Build

```bash
tools/build_web.sh        # → web-dist/  (requires brotli + binaryen's wasm-opt)
```

What it does:

1. **Release export** of the `Web` preset (smaller than the debug template).
2. **`wasm-opt`** — strips debug/producer sections and `-Oz` the engine wasm.
3. **Brotli `-q 11`** the two heavy files → `index.wasm.br`, `index.pck.br`.
   (Measured: ~37.7 MB wasm → ~34.6 MB after wasm-opt → ~6.5 MB brotli; pck
   ~15.9 MB → ~7.7 MB brotli. Brotli beats gzip by ~8 MB total here.)
4. **Assembles `web-dist/`** with the shipped assets, the vendored brotli decoder
   (`vendor/brotli_dec_wasm*`), and `mb_brotli_boot.js`, and injects the shim
   into `index.html`.

## Why client-side decompression (not `Content-Encoding: br`)

The clean way to serve compressed wasm is to ship `.br` files and let the server
send `Content-Encoding: br` so the browser decompresses transparently. **Amplify
can't do this**: it treats `Content-Encoding` as a read-only header and fails the
build if you set it in `customHttp.yml`, and CloudFront's automatic compression
skips `application/wasm` and any file over 10 MB.

So `mb_brotli_boot.js` installs a `window.fetch` wrapper (in `<head>`, before
`index.js`) that intercepts requests for `index.wasm` / `index.pck`, fetches the
`.br` sibling, brotli-decompresses it in the browser, and returns a synthetic
`Response`. Godot's loader is never patched, so it survives engine upgrades, and
the bundle works on **any** dumb static host.

Threads are disabled in the Web preset, so no `SharedArrayBuffer` and **no
COOP/COEP cross-origin-isolation headers are required**.

## Deploy

Amplify config lives at the repo root:

- `amplify.yml` — no build step; publishes `web-dist/`.
- `customHttp.yml` — caching + content types (no compression headers).

To ship an update: `tools/build_web.sh`, then commit `web-dist/` and push to the
Amplify-connected branch.

> Caching note: Godot emits **stable, un-hashed filenames**. `customHttp.yml`
> uses `max-age=0, must-revalidate` so a redeploy is picked up immediately (ETag
> → 304 when unchanged). Don't switch these to `immutable` unless the filenames
> become content-hashed.

## Deferred (Phase 2): custom engine templates

The biggest *uncompressed*-size wins (disable 3D, `optimize=size_extra`, strip
the advanced text server / advanced GUI / unused modules) require compiling
custom Godot export templates from source (SCons + emscripten). Not done here —
revisit if uncompressed footprint becomes a problem.
