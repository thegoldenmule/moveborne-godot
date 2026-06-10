# Bug report: `snapctl byosnap sync` fails with misleading errors for any not-yet-published version

**snapctl version:** 1.10.0 (pipx install, Python 3.14.5)
**OS:** macOS (Darwin 25.3.0, Apple Silicon)
**Docker:** 29.4.1 (Docker Desktop, context `desktop-linux`, buildx v0.33.0)
**App / snapend:** `c4n1awfs` (DEVELOPMENT), BYOSnap `byosnap-metagame` (Go, linux/arm64)
**Date observed:** 2026-06-10

## Summary

`snapctl byosnap sync` only works when `--version` names a version that was **already created
by a prior `snapctl byosnap publish`**. For any other version it fails *after* pushing the
image, with the misleading error `BYOSnap not found.` — even though the BYOSnap exists and is
attached to the snapend. For a BYOSnap that does not exist at all, it fails up front with the
equally misleading `Service ID is invalid.` Neither the docs nor the error text mention the
real precondition (version must pre-exist), and each failed run leaves an orphaned image tag
in the registry.

## Exact commands and results (chronological)

### 1. sync before the BYOSnap existed → `Service ID is invalid.`

```bash
snapctl byosnap sync --byosnap-id byosnap-metagame \
    --path /tmp/byosnap-metagame-ctx --resources-path /tmp/byosnap-metagame-ctx/metagame \
    --version v0.0.1 --snapend-id c4n1awfs --blocking
# -> Error Service ID is invalid.
# -> {"error": true, "code": 2, "msg": "Service ID is invalid.", "data": null}
```

### 2. first-time flow that works: publish + snapend update

```bash
snapctl byosnap publish --byosnap-id byosnap-metagame --version v0.0.1 \
    --path /tmp/byosnap-metagame-ctx --resources-path /tmp/byosnap-metagame-ctx/metagame
# -> BYOSNAP publish successful (image pushed, version v0.0.1 created)

snapctl snapend update --snapend-id c4n1awfs \
    --byosnaps byosnap-validator:c4n1awfs,byosnap-metagame:v0.0.1 --blocking
# -> Snapend update successful. Snapend Live; byosnap-metagame serving traffic.
```

### 3. sync with a NEW version, BYOSnap now existing and attached → image pushed, then `BYOSnap not found.`

```bash
snapctl byosnap sync --byosnap-id byosnap-metagame \
    --path /tmp/byosnap-metagame-ctx --resources-path /tmp/byosnap-metagame-ctx/metagame \
    --version v0.0.2 --snapend-id c4n1awfs --blocking
# -> byosnap-metagame.v0.0.2-1781119952: digest: sha256:973b6ac26548c3... size: 3022
# -> Success BYOSnap upload successful
# -> Success BYOSNAP publish image successful
# -> Error BYOSnap not found.
# -> {"error": true, "code": 3, "msg": "BYOSnap not found.", "data": null}
```

(v0.0.2 was subsequently created via `publish --version v0.0.2`, which succeeded, and the
snapend updated to it.)

### 4. repro with `--verbose`, new version v0.0.3 → identical failure

```bash
snapctl byosnap sync --byosnap-id byosnap-metagame \
    --path /tmp/byosnap-metagame-ctx --resources-path /tmp/byosnap-metagame-ctx/metagame \
    --version v0.0.3 --snapend-id c4n1awfs --blocking --verbose
# exit code 3
# -> byosnap-metagame.v0.0.3-1781120865: digest: sha256:973b6ac26548c3... size: 3022
# -> Success BYOSnap upload successful
# -> Success BYOSNAP publish image successful
# -> Error BYOSnap not found.
```

`--verbose` adds docker build/push detail only; snapctl's own API calls are not traced.

### 5. control: sync with an ALREADY-PUBLISHED version → full success

```bash
snapctl byosnap sync --byosnap-id byosnap-metagame \
    --path /tmp/byosnap-metagame-ctx --resources-path /tmp/byosnap-metagame-ctx/metagame \
    --version v0.0.2 --snapend-id c4n1awfs --blocking
# -> Success Updated your snapend. Your snapend is Live.
# -> {"error": false, "code": 0, "msg": "BYOSNAP sync successful", "data": null}
```

## Root cause (from snapctl 1.10.0 source, `site-packages/snapctl/`)

`Byosnap.sync()` (`commands/byosnap.py:1382`) does:

1. tag the image `{version}-{unix_ts}` and `build_tag_push()` — succeeds;
2. `update_version()` (`commands/byosnap.py:1257`), which issues
   `PATCH {base_url}/v1/snapser-api/byosnaps/{byosnap_id}/versions/{version}`
   (`commands/byosnap.py:1283`) to point the **existing** version record at the new image tag.

`sync` never calls `publish_version` (only `publish()` does), so if `--version` names a
version that has never been published, the PATCH returns `HTTP_ERROR_RESOURCE_NOT_FOUND` and
snapctl reports it as `BYOSnap not found.` (`commands/byosnap.py:1294`) — wrong object: the
BYOSnap exists; the *version* doesn't.

The pre-existence failure (case 1) comes from `get_composite_token`
(`utils/helper.py:75`): the composite-token exchange returns 404 for a non-existent service
and snapctl maps any 404 there to `Service ID is invalid.`

## Why this is worth fixing

- **Misleading errors:** both messages point at the wrong object (`Service ID` / `BYOSnap`)
  when the actual missing resource is the *version record*. Cost us several failed deploys
  before reading the CLI source.
- **Docs mismatch:** the CLI reference describes sync as "rapidly build, update and push
  their BYOSnap to a dev Snapend" with no mention that `--version` must already exist via
  `publish`. The only hint is an unrelated note about `--tag` matching the version for
  `--skip-build`.
- **Non-transactional failure:** the image is built and pushed *before* the version check,
  so every failed sync orphans a tag in the customer ECR repo
  (here: `byosnap-metagame.v0.0.2-1781119952`, `byosnap-metagame.v0.0.3-1781120865`).

## Workaround we use

First deploy and every new version: `publish` then `snapend update` (section 2 above).
`sync` only for re-pushing code under an already-published version (section 5).
