# Build &amp; Distribution

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

Known follow-ups, deliberately deferred: the presets export all resources, so the addons, tests, tools, and art/generated trees all ship inside the release pack (bloat), and the dev autoloads (MbDebug and the godot-ai runtime helper) are included — both no-op safely at runtime but should be stripped for a real release via exclude filters and a release-only autoload trim. There is also no CI yet; builds are host-local.

## Components
_No components._

## Dependencies
_No dependencies._

## Code references
- `game/export_presets.cfg`
- `tools/build.sh`
- constant `import_etc2_astc / config/name` in `game/project.godot`

## Data model
Preset → output map (friendly name → preset name in `export_presets.cfg` → artifact):

| Friendly | Preset | Output | Host status |
|---|---|---|---|
| `macos` | macOS | `build/macos/Moveborne.zip` (universal `.app`) | turnkey |
| `windows` | Windows Desktop | `build/windows/Moveborne.exe` (+ `.pck`, console exe) | turnkey |
| `web` | Web | `build/web/index.html` (+ `.wasm`/`.pck`/`.js`) | turnkey |
| `ios` | iOS | `build/ios/Moveborne.ipa` | needs Xcode + Apple signing |
| `android` | Android | `build/android/Moveborne.apk` | needs JDK 17 + SDK + Gradle template + keystore |

Signing/secret config is read from a gitignored `<repo>/.env` (sourced by the script): `ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASS`, `APPLE_TEAM_ID`, `APPLE_SIGN_IDENTITY`. Bundle id / package name for both mobile presets is `com.thegoldenmule.moveborne`.

## Usage
Run from the repo root:

- `tools/build.sh macos` — one platform
- `tools/build.sh web windows` — any subset
- `tools/build.sh all` — every platform
- `tools/build.sh --release all` — release export (default is **debug**)
- `tools/build.sh --list` — list platform names

The engine is `/Applications/Godot.app/Contents/MacOS/Godot` by default; override with `GODOT=/path/to/Godot tools/build.sh …`. Each export runs `godot --headless --path game --export-{debug,release} "<preset>" <output>`; the script reports per-platform ✓/✗ from the actual export exit code (not from the ArtGen/godot-ai editor-plugin chatter the headless scan prints) and exits non-zero if any target failed. Artifacts land under `build/<platform>/` (gitignored). For the web build it prints the local-serve hint (`cd build/web && python3 -m http.server 8000`).

## Invariants & constraints
- Export presets are committed and source-of-truth: `game/export_presets.cfg` is reviewed config, not per-machine editor state. Build output goes to gitignored `build/<platform>/`.
- One export invocation per platform — Godot has no export-all; `tools/build.sh` is the only place the multi-platform / subset / all selection lives.
- Secrets never enter the repo or the presets: signing material is read at build time from a gitignored `.env`.
- Build configuration must not change deterministic logic — the ETC2 ASTC import and app-name settings are presentation/packaging only, so parity hashes are untouched.

## Synced commit
9fb6c8f
