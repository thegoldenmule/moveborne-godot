- Default to using Bun instead of Node.js.
- Use `bun <file>` instead of `node <file>` or `ts-node <file>`
- Use `bun test` instead of `jest` or `vitest`
- Use `bun build <file.html|file.ts|file.css>` instead of `webpack` or `esbuild`
- Use `bun install` instead of `npm install` or `yarn install` or `pnpm install`
- Use `bun run <script>` instead of `npm run <script>` or `yarn run <script>` or `pnpm run <script>`
- Bun automatically loads .env, so don't use dotenv.
- DO NOT kill or restart the validator server - it runs with `bun run --watch` which automatically reloads on file changes.

## MCP Interface

The validator exposes an MCP server at `http://localhost:5555/mcp` for inspecting and debugging match state.

**list_matches**: Lists all active matches in the validator store with basic metadata (match_id, player_id, action_count, moveIndex, gameStatus, timestamps).

**get_match_state**: Retrieves the complete state for a specific match including game state, RNG indices, and computed state hash. Requires `match_id` parameter.

**get_state_history**: Retrieves the full state history for a match (moveIndex -> state mapping). Returns an array of all states stored during the match session, sorted by moveIndex. Each state includes game status, score, shards, combo, tiles, RNG indices, hand, deck, and computed state hash. Requires `match_id` parameter. Useful for debugging state synchronization issues.

**simulate_action**: Simulates an action without applying it to see the result. Requires `match_id`, `action_type` (SWIPE or PLAY_CARD), and `action_payload` (JSON string). Returns success status, state hashes, score/shard deltas, and updated RNG indices.

**clear_match**: Removes a match from the validator store. Requires `match_id` parameter.

## State History Replay

The validator supports initializing matches from saved state histories via `POST /api/match/init-from-history`.

**Request body:**
- `history_file_id` (optional): ID of fixture file in `src/game/fixtures/history/{id}.json`
- `history_data` (optional): Array of StateHistorySnapshot objects
- `start_from_index` (optional): moveIndex to start from (defaults to last state)
- `player_id` (required): Player identifier
- `signature` (required): Authentication signature

One of `history_file_id` or `history_data` must be provided.

**Response:** Same as `/init` endpoint (connection_id, expires_at)

**Example:**
```bash
curl -X POST http://localhost:5555/api/match/init-from-history \
  -H "Content-Type: application/json" \
  -d '{
    "history_file_id": "hash-mismatch-debug",
    "start_from_index": 5,
    "player_id": "test-player-1",
    "signature": "test-signature"
  }'
```

This loads all states from the history into the validator's state_history Map and sets current_state to the specified moveIndex.