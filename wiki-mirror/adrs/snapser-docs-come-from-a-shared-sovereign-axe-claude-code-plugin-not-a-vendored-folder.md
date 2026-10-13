# Snapser docs come from a shared Sovereign Axe Claude Code plugin, not a vendored folder

**Status:** accepted

## Metadata
- **Number:** ADR-27
- **Date:** 2026-10-12
- **Scope:** agent tooling / reference docs (all Sovereign Axe games using Snapser)
- **Deciders:** Benjamin Jordan

## Context
Snapser's online documentation is unavailable, so agents working on Snapser integrations need a local copy of the platform docs and the per-snap OpenAPI swaggers. Until now each game vendored its own copy: moveborne-godot carried a `snapser-docs/` folder (188 `.mdx` pages + 33 swaggers, committed 2026-06-09) and Sovereign-Battleships carries another. Copies drift independently and every new game has to re-vendor. A Godot addon was considered and rejected: the only consumer of the docs is the coding agent, never the Godot editor or runtime, so an addon would still mean one copy per game inside `res://` (and the swagger `.json` files would be picked up as Godot resources). Snapser's own Claude Code plugin (`snapser-agent-plugin`, shipped inside Forge.app) bundles a newer superset — more pages, the same swaggers, plus release notes — but it is installed from a local folder inside the Forge app bundle, so only machines with Forge installed get it. Its data is Snapser-proprietary; Snapser has granted us permission to use it across our projects.

## Decision
The Snapser docs live in ONE private repo, Sovereign-Axe-Studios/snapser-docs (local clone: ~/projects/sovereign-axe/snapser-docs), packaged as a Claude Code plugin marketplace named sovereign-axe-snapser containing a single plugin, snapser-docs. The plugin's snapser-docs skill bundles docs/ (platform .mdx), swagger/ (per-snap OpenAPI 3 specs, the authority for endpoints, verbs, bodies and x-snapser-auth-types), releases/ (platform release notes, INDEX.md first) and SOURCE.json (the upstream build the snapshot came from), and tells the agent where to look for each kind of question.

The content is seeded from Snapser's agent-plugin data (via Forge.app), used under Snapser's permission. The repo must stay private: the permission covers our use, not public redistribution. Refreshing is scripts/sync-from-forge.sh (mirrors docs, swaggers, release notes and SOURCE.json from the installed Forge.app, or from a path to a snapser-agent-plugin checkout), then bump the plugin version and push.

Each game opts in by committing the marketplace and plugin to its .claude/settings.json (extraKnownMarketplaces: sovereign-axe-snapser from github Sovereign-Axe-Studios/snapser-docs; enabledPlugins: snapser-docs@sovereign-axe-snapser). Anyone who trusts the repo is prompted to install it, cloning with their own GitHub credentials. Games no longer vendor a snapser-docs/ folder; moveborne-godot's was removed.

```json
{
  "extraKnownMarketplaces": {
    "sovereign-axe-snapser": {
      "source": { "source": "github", "repo": "Sovereign-Axe-Studios/snapser-docs" }
    }
  },
  "enabledPlugins": {
    "snapser-docs@sovereign-axe-snapser": true
  }
}
```

## Consequences
One copy of the Snapser docs for every game, updated with a single push; consumers pick it up with claude plugin marketplace update sovereign-axe-snapser.

No dependency on Forge.app being installed for reading docs: teammates, fresh clones and other machines get the docs from GitHub. Forge is only needed to refresh the snapshot.

Access requires read access to the private Sovereign-Axe-Studios/snapser-docs repo; a machine without GitHub credentials for the org cannot install the plugin.

Swagger references in code comments (quests, leaderboards, profiles clients and tests) now point at the snapser-docs plugin's swagger/ directory rather than a path inside this repo.

The Admin SDK bundled in Snapser's agent plugin is not mirrored (it is SDK code, not docs); the Forge snapser plugin remains the source for its operational skills (publish BYOSnap, configure snap settings, etc.).

Other games still vendoring their own copy (e.g. Sovereign-Battleships/snapser-docs/) should migrate to the plugin the same way.

## Relations
_None._
