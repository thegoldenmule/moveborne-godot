# ADR-18: Script-driven multi-platform export; commit presets, defer CI

**Status:** accepted

## Metadata
- **Date:** 2026-06-11
- **Scope:** Client / Build & Distribution
- **Deciders:** Benjamin Jordan

## Context
The Godot client targets five platforms (macOS, Windows, Web, iOS, Android) and needs repeatable builds for any one, any subset, or all of them. Godot's export configuration normally lives in `export_presets.cfg`, which is often treated as per-machine editor state, and the engine has no single-command "export all" — each preset is a separate `--export-release/--export-debug` invocation. There was no build tooling in the repo yet (no `export_presets.cfg`, no CI). The dev host is macOS, which can cross-export all five targets and is mandatory for iOS/macOS.

## Decision
Commit a single Godot export-presets file to the repo (one preset per platform: macOS, Windows, Web, iOS, Android) and drive it with a thin shell script, tools/build.sh, that loops one headless export per requested platform and accepts any subset or the keyword all. Default to debug exports; pass --release for release. Cross-export every target from the macOS dev host. Read signing material (Android keystore, Apple identity) at build time from a gitignored .env. Do not stand up CI yet — keep builds host-local, with the committed presets ready to be reused by a CI matrix later.

## Consequences
POSITIVE: Export configuration is source-controlled and reviewable, not trapped in per-machine editor state. Building any subset or all platforms is one command with no extra toolchain (no Make, no CI runner), matching the repo's existing tools shell-script convention. macOS, Windows, and Web build and run from this host immediately; the web build serves from a plain static server because thread support is disabled (no cross-origin-isolation headers needed).

NEGATIVE / COST: No reproducible CI builds yet, so release artifacts depend on the dev machine's installed export templates and toolchains. iOS and Android still need their platform toolchains and signing material wired through .env before they produce artifacts. Because the presets currently export all resources, dev-only addons, the tests and tools trees, and the MbDebug autoload ship inside release packs until exclude filters and a release-only autoload trim are added.

## Relations
_None._
