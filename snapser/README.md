# Snapser snapend IaC

`snapend-manifest.json` is the manifest for snapend **c4n1awfs** (the `dev` snapend behind
`https://gateway.snapser.com/c4n1awfs`), kept in-repo as infrastructure-as-code. It was
exported with `snapctl snapend download --category snapend-manifest` and then edited; the
only intentional delta from the live export is the `settings[id=leaderboards].data.leaderboards`
block, which defines the three boards the game client uses (see
`game/net/leaderboards_client.gd` — the names are load-bearing):

| Board | Recurrence | Anchor (UTC) |
|---|---|---|
| `moveborne-daily` | 1 day | 2026-06-10 00:00 |
| `moveborne-weekly` | 1 week | Mon 2026-06-08 00:00 |
| `moveborne-monthly` | 1 month | 2026-06-01 00:00 |

All three: `type=global`, `behavior=maximum` (server keeps the period's best score, so blind
re-submits are safe), `sort=descending`, `scope=external` (client-writable — interim posture
until the validator reports scores, at which point scope flips/SetScore gets locked via Auth
User Auth Restrictions).

Deploy:

```bash
snapctl snapend apply --manifest-path-filename snapser/snapend-manifest.json --blocking
```

`apply` diffs the embedded `applied_configuration` against the live snapend and refuses to
stomp manual changes (use `--force` only deliberately). Snap *settings* schemas (the board
definition fields/enums) are validated server-side at apply time; if the platform rejects an
enum string, fix it here and re-apply, then re-download so `applied_configuration` is fresh.

BYOSnap deploys (validator, metagame) are **not** done through this manifest — they keep
their own publish + `snapend update` loop (see each service's README).
