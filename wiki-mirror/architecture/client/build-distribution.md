# Build & Distribution

**Status:** current

## Kind
subsystem

## Summary
The client build system: a single committed `game/export_presets.cfg` (one preset per platform — macOS, Windows, Web, iOS, Android) driven by `tools/build.sh`, which loops one headless Godot export per requested platform. Godot has no native "export all" flag, so the script is the layer that turns "build any subset, or all" into one command. All five targets cross-export from the macOS dev host; macOS/Windows/Web are turnkey today, while iOS/Android additionally need their platform toolchains and signing material.

## Purpose
Moveborne needs reproducible, repeatable builds for five platforms without hand-driving the editor's Export dialog each time. Committing the presets makes the export configuration source-controlled and reviewable (not per-machine editor state), and a thin shell wrapper keeps the workflow dependency-free — no Makefile, no CI runner — matching the repo's existing `tools/*.sh` convention. The design deliberately favours a host-local script first; a CI matrix is a clean later addition that reuses the same presets.

## Design notes
Two project-setting changes were load-bearing for export. The app name was set to Moveborne (it was the LLM Workflow placeholder), which becomes the macOS bundle name and Android label. And the ETC2 ASTC texture import was enabled under rendering / textures / VRAM compression — Godot refuses to export macOS arm64 or universal (and Android) with that import disabled. Neither touches deterministic logic, so parity hashes are unaffected.

macOS codesign and notarization are disabled in the preset, and Web thread support is off. Disabling web threads is what lets the build serve from a plain static server with no COOP/COEP cross-origin-isolation headers (SharedArrayBuffer would otherwise require them). Distribution-grade macOS builds (Developer ID plus notarytool) and threaded web are deferred.

Web hosting (AWS Amplify). The plain `web` preset output is post-processed for static hosting by a second script, `tools/build_web.sh`, into a committed `web-dist/` tree that Amplify publishes as-is (no Amplify build step). The pipeline: release export → `wasm-opt --strip-debug --strip-producers -Oz` on the engine wasm → `brotli -q 11` of the two heavy files (`index.wasm`, `index.pck`). Measured ~53 MB uncompressed → ~13.8 MB transferred; brotli beats gzip by ~8 MB here, mostly on the pck (7.4 vs 13.2 MB). Compression is done CLIENT-SIDE, not via `Content-Encoding: br` — Amplify treats `Content-Encoding` as a read-only header and fails the build if you set it, and CloudFront won't auto-compress `application/wasm` or files over 10 MB. So `tools/web/mb_brotli_boot.js` (a classic `<script>` injected into `<head>` before `index.js`) installs a `window.fetch` wrapper that redirects requests for `index.wasm`/`index.pck` to their `.br` siblings, brotli-decompresses them in-browser via a vendored `brotli-dec-wasm` decoder (~208 KB wasm), and returns a synthetic `Response`. Godot's loader is never patched, so this survives engine upgrades and the bundle runs on any dumb static host. The game's own in-engine cross-origin `fetch` (Snapser) passes through untouched, and with web threads off no COOP/COEP is required.

Amplify config lives at the repo root: `amplify.yml` (no build phase; `baseDirectory: web-dist`) and `customHttp.yml` (caching + content types only — no compression headers). Godot emits stable, un-hashed filenames, so the big assets use `Cache-Control: max-age=0, must-revalidate` (ETag → cheap 304 when unchanged, full re-download after a redeploy); don't switch them to `immutable` unless the filenames become content-hashed. Verified booting in-browser: the engine instantiates, the pck loads, anon Snapser login + inventory fetch succeed, and the main menu renders. The bigger uncompressed-size wins — custom engine templates (disable 3D, `optimize=size_extra`, strip the advanced text-server / advanced GUI / unused modules) — need a SCons + emscripten build and remain deferred.

Known follow-ups, deliberately deferred: the presets still export all resources, so the addons, tests, tools, and art/generated trees ship inside the release pack (bloat) and the dev autoloads (MbDebug and the godot-ai runtime helper) are included — both no-op at runtime, though the godot-ai helper logs a harmless `EditorInterface not declared` parse error in exported (non-editor) builds, and both should be stripped for a real release via exclude filters + a release-only autoload trim. The hosted web path now has its own size optimization (`tools/build_web.sh`), but addon/test/tool stripping is still open and would further shrink the pck. There is still no CI; builds are host-local.

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- `game/export_presets.cfg`
- `tools/build.sh`
- constant `import_etc2_astc / config/name` in `game/project.godot`
- `tools/build_web.sh`
- `tools/web/mb_brotli_boot.js`
- `amplify.yml`
- `customHttp.yml`

## Data model
Preset → output map (friendly name → preset name in `export_presets.cfg` → artifact):

| Friendly | Preset | Output | Host status |
|---|---|---|---|
| `macos` | macOS | `build/macos/Moveborne.zip` (universal `.app`) | turnkey |
| `windows` | Windows Desktop | `build/windows/Moveborne.exe` (+ `.pck`, console exe) | turnkey |
| `web` | Web | `build/web/index.html` (+ `.wasm`/`.pck`/`.js`) | turnkey; hosted bundle via `tools/build_web.sh` → `web-dist/` |
| `ios` | iOS | `build/ios/Moveborne.ipa` | needs Xcode + Apple signing |
| `android` | Android | `build/android/Moveborne.apk` | needs JDK 17 + SDK + Gradle template + keystore |

Signing/secret config is read from a gitignored `<repo>/.env` (sourced by the script): `ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASS`, `APPLE_TEAM_ID`, `APPLE_SIGN_IDENTITY`. Bundle id / package name for both mobile presets is `com.thegoldenmule.moveborne`.

The hosted web bundle in `web-dist/` (committed, served by Amplify) replaces the two heavy files with brotli'd siblings and adds the decoder + shim: `index.wasm.br` (~6.2 MB), `index.pck.br` (~7.4 MB), `brotli_dec_wasm.js` + `brotli_dec_wasm_bg.wasm` (vendored decoder, ~0.21 MB), `mb_brotli_boot.js`, plus the unchanged `index.html` (shim injected), `index.js`, audio worklets, icons, and splash. Repo-root `amplify.yml` + `customHttp.yml` configure the deploy.

## Usage
Run from the repo root:

- `tools/build.sh macos` — one platform
- `tools/build.sh web windows` — any subset
- `tools/build.sh all` — every platform
- `tools/build.sh --release all` — release export (default is **debug**)
- `tools/build.sh --list` — list platform names

The engine is `/Applications/Godot.app/Contents/MacOS/Godot` by default; override with `GODOT=/path/to/Godot tools/build.sh …`. Each export runs `godot --headless --path game --export-{debug,release} "<preset>" <output>`; the script reports per-platform ✓/✗ from the actual export exit code (not from the ArtGen/godot-ai editor-plugin chatter the headless scan prints) and exits non-zero if any target failed. Artifacts land under `build/<platform>/` (gitignored). For the web build it prints the local-serve hint (`cd build/web && python3 -m http.server 8000`).

**Hosted web build (Amplify):** `tools/build_web.sh` is a separate one-command pipeline that produces the optimized, brotli-compressed bundle in `web-dist/` (release export + `wasm-opt` + brotli + the in-browser decompression shim). It requires `brotli` and binaryen's `wasm-opt` (`brew install binaryen`; wasm-opt is skipped with a warning if absent). Preview with `cd web-dist && python3 -m http.server 8000`. To deploy, commit `web-dist/` + `customHttp.yml` + `amplify.yml` and push to the Amplify-connected branch. See `tools/web/README.md`.

## Invariants & constraints
- Export presets are committed and source-of-truth: `game/export_presets.cfg` is reviewed config, not per-machine editor state. Build output goes to gitignored `build/<platform>/`.
- One export invocation per platform — Godot has no export-all; `tools/build.sh` is the only place the multi-platform / subset / all selection lives.
- Secrets never enter the repo or the presets: signing material is read at build time from a gitignored `.env`.
- Build configuration must not change deterministic logic — the ETC2 ASTC import and app-name settings are presentation/packaging only, so parity hashes are untouched.
- The hosted web bundle compresses the engine `.wasm`/`.pck` with brotli and decompresses them CLIENT-SIDE (the `mb_brotli_boot.js` fetch shim), never via `Content-Encoding` — Amplify rejects that as a read-only header. `web-dist/` is committed and served as-is; raw per-platform exports stay gitignored under `build/<platform>/`.

## Synced commit
109714d
