# Run Validator Skill - API Reference

## Overview

The Moveborne validator server is a Bun-based service that validates game logic, manages match state, and provides debugging tools through an MCP interface. It runs on port 5555 (HTTP/WebSocket) and exposes MCP tools at port 5555.

## Server Management

### Starting the Validator

The validator should be run with Bun's watch mode for automatic hot-reload during development.

**From project root:**
```bash
cd validator/src/validator && bun run dev
```

**Using skill scripts:**
```bash
.claude/skills/run-validator/scripts/start-validator.sh
```

**What happens:**
- Starts Bun server with `--watch` flag
- Loads environment variables from `.env`
- Serves the Hermes-emulation WebSocket (`/hermes/ws`) + gRPC (:8081) for game validation
- Starts MCP server on port 5555
- Monitors file changes for automatic reload

### Checking Status

**Check if running (using lsof):**
```bash
lsof -i :5555
```

**Check if running (using curl):**
```bash
curl http://localhost:5555/health
```

**Using skill scripts:**
```bash
.claude/skills/run-validator/scripts/check-validator.sh
```

### Stopping the Validator

The validator should generally NOT be stopped during development since it auto-reloads on changes. However, when necessary:

**Find and kill process:**
```bash
pkill -f "bun run --watch index.ts"
```

**Or by port:**
```bash
lsof -ti :5555 | xargs kill -9
```

**Using skill scripts:**
```bash
.claude/skills/run-validator/scripts/stop-validator.sh
```

### Restarting

Only restart when hot-reload isn't sufficient (e.g., environment variable changes):

```bash
.claude/skills/run-validator/scripts/stop-validator.sh
.claude/skills/run-validator/scripts/start-validator.sh
```

## MCP Tools

The validator exposes five MCP tools through the JSON-RPC interface at `http://localhost:5555/mcp`.

### mcp__validator__list_matches

List all active matches in the validator store.

**Parameters:** None

**Returns:** Array of match metadata objects:
```typescript
{
  match_id: string;
  player_id: string;
  action_count: number;
  moveIndex: number;
  gameStatus: string;
  created_at: string;
  last_action_at: string;
}
```

**Example:**
```typescript
Tool: mcp__validator__list_matches
```

**Use Cases:**
- See all active game sessions
- Find match_id for further inspection
- Monitor validator load
- Identify stale matches

### mcp__validator__get_match_state

Get the complete current state for a specific match.

**Parameters:**
- `match_id` (required): The match identifier

**Returns:** Match state object:
```typescript
{
  match_id: string;
  player_id: string;
  current_state: {
    gameStatus: string;
    score: number;
    shards: number;
    combo: number;
    tiles: ITile[][];
    hand: ICard[];
    deck: string[];
    playerStats: {
      health: number;
      maxHealth: number;
      energy: number;
      maxEnergy: number;
      armor: number;
    };
    turn: number;
    moveIndex: number;
  };
  rng_monster_index: number;
  rng_loot_index: number;
  computed_hash: string;
}
```

**Example:**
```typescript
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "test-match-1234567890"
```

**Use Cases:**
- Inspect current game state
- Verify state synchronization
- Check computed hash
- Debug specific match issues

### mcp__validator__get_state_history

Get the full state history for a match (all moveIndex snapshots).

**Parameters:**
- `match_id` (required): The match identifier

**Returns:** Object with history array:
```typescript
{
  match_id: string;
  history: Array<{
    moveIndex: number;
    state: {
      gameStatus: string;
      score: number;
      shards: number;
      combo: number;
      tiles: ITile[][];
      hand: ICard[];
      deck: string[];
      playerStats: IPlayerStats;
      turn: number;
      moveIndex: number;
    };
    rng_monster_index: number;
    rng_loot_index: number;
    computed_hash: string;
  }>;
}
```

**Example:**
```typescript
Tool: mcp__validator__get_state_history
Parameters:
  match_id: "test-match-1234567890"
```

**Use Cases:**
- Debug state progression issues
- Compare states across moves
- Track hash changes over time
- Reproduce bugs from specific moveIndex
- Analyze RNG progression

### mcp__validator__simulate_action

Simulate a game action without applying it to see the predicted result.

**Parameters:**
- `match_id` (required): The match identifier
- `action_type` (required): `"SWIPE"` or `"PLAY_CARD"`
- `action_payload` (required): JSON string of action data

**Action Payloads:**

For SWIPE:
```json
{"direction": "up"}
// or "down", "left", "right"
```

For PLAY_CARD:
```json
{"cardIndex": 0, "targetRow": 2, "targetCol": 3}
```

**Returns:** Simulation result:
```typescript
{
  success: boolean;
  error?: string;
  preview: {
    current_hash: string;
    predicted_hash: string;
    score_delta: number;
    shards_delta: number;
    new_rng_monster_index: number;
    new_rng_loot_index: number;
  };
}
```

**Example:**
```typescript
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "test-match-1234567890"
  action_type: "SWIPE"
  action_payload: "{\"direction\":\"up\"}"
```

**Use Cases:**
- Test actions before executing
- Validate action legality
- Preview state changes
- Check hash computation
- Debug action logic

### mcp__validator__clear_match

Remove a match from the validator store.

**Parameters:**
- `match_id` (required): The match identifier

**Returns:**
```typescript
{
  success: boolean;
  message: string;
}
```

**Example:**
```typescript
Tool: mcp__validator__clear_match
Parameters:
  match_id: "test-match-1234567890"
```

**Use Cases:**
- Clean up test matches
- Free memory from old sessions
- Reset for new test runs
- Remove corrupted match state

## HTTP API Endpoints

### Match RPCs (gRPC / Hermes — not HTTP)

Game-facing match calls (InitMatch, ValidateAction, CompleteMatch) are a gRPC
service (`moveborne.validator.v1.ValidatorService`, protos in `validator/protos/`),
reached locally through the Hermes-emulation WebSocket
(`ws://localhost:5555/hermes/ws?token=<player-id>`, binary protobuf
ClientMessage/ServerMessage frames) or directly via gRPC on `localhost:8081`.
There is no HTTP init endpoint and no connection_id lifecycle anymore; use the
MCP tools below (or `game/tools/test_validator_client.gd`) to create and drive
matches when testing.

### POST /api/match/init-from-history

Initialize a match from saved state history.

**Request Body:**
```json
{
  "history_file_id": "hash-mismatch-debug",
  "start_from_index": 5,
  "player_id": "test-player-1",
  "signature": "test-signature"
}
```

**Or with inline data:**
```json
{
  "history_data": [
    {
      "moveIndex": 0,
      "timestamp": 1234567890,
      "state": { /* SynchronizedGameState */ }
    }
  ],
  "player_id": "test-player-1",
  "signature": "test-signature"
}
```

**Response:** Same as `/init` endpoint

**Parameters:**
- `history_file_id` (optional): ID of fixture in `src/game/fixtures/history/{id}.json`
- `history_data` (optional): Array of StateHistorySnapshot objects
- `start_from_index` (optional): moveIndex to start from (defaults to last)
- `player_id` (required): Player identifier
- `signature` (required): Authentication signature

**Notes:**
- One of `history_file_id` or `history_data` must be provided
- All states are loaded into validator's state_history Map
- Current state is set to specified moveIndex
- Useful for reproducing bugs and testing edge cases

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "timestamp": 1234567890
}
```

## Configuration

### Environment Variables

Loaded automatically by Bun from `validator/src/validator/.env`:

```bash
VALIDATOR_SHARED_SECRET=dev-shared-secret-change-me
PORT=5555
GRPC_PORT=8081
MATCH_SESSION_TTL=3600
```

Auth has no bypass switch: every RPC binds the gateway-validated identity to the
match owner (`player_id`). Locally the Hermes-emulation WS takes the self-stamped
player id as its `?token=` query param; HTTP history routes still take a
`User-Id` header; api-key/internal callers pass unbound.

### Port Configuration

- **5555** (`PORT`): HTTP (health/status/history), the Hermes-emulation
  WebSocket (`/hermes/ws`), and the MCP JSON-RPC interface (`/mcp`).
- **8081** (`GRPC_PORT`): the gRPC ValidatorService (same port deployed; HTTP
  stays on 8080 behind the gateway).

Change the port by modifying the `.env` file. Restart required after changing env vars.

## State Structure

### Match State

Complete state stored for each match:

```typescript
interface IMatchState {
  match_id: string;
  player_id: string;
  current_state: ISynchronizedGameState;
  state_history: Map<number, IStateSnapshot>;
  rng_monster_index: number;
  rng_loot_index: number;
  action_count: number;
  created_at: Date;
  last_action_at: Date;
}
```

### State Snapshot

Stored in history map by moveIndex:

```typescript
interface IStateSnapshot {
  moveIndex: number;
  state: ISynchronizedGameState;
  rng_monster_index: number;
  rng_loot_index: number;
  computed_hash: string;
  timestamp: number;
}
```

### Synchronized Game State

The core game state object:

```typescript
interface ISynchronizedGameState {
  gameStatus: "ONGOING" | "WON" | "LOST";
  score: number;
  shards: number;
  combo: number;
  tiles: ITile[][];
  hand: ICard[];
  deck: string[];
  playerStats: {
    health: number;
    maxHealth: number;
    energy: number;
    maxEnergy: number;
    armor: number;
  };
  turn: number;
  moveIndex: number;
}
```

## Hash Validation

The validator computes deterministic hashes for state validation:

1. Hash is computed from serialized state + RNG indices
2. Client sends action with expected next hash
3. Validator computes actual next hash
4. If mismatch, action is rejected
5. History stores all hashes for debugging

**Hash includes:**
- Game state (board, hand, deck, stats)
- RNG indices (monster, loot)
- Turn and moveIndex

**Use for:**
- Detecting state desync
- Validating deterministic behavior
- Catching client tampering
- Debugging reproducibility

## Best Practices

### 1. Use Watch Mode

Always run with `bun run dev` for hot-reload:
```bash
cd validator/src/validator && bun run dev
```

### 2. Check Before Starting

Verify no existing process:
```bash
lsof -i :5555
```

### 3. Clean Up Test Matches

Clear old matches after testing:
```typescript
Tool: mcp__validator__clear_match
Parameters:
  match_id: "test-match-id"
```

### 4. Use Simulation First

Test actions with simulate before executing:
```typescript
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "match-id"
  action_type: "SWIPE"
  action_payload: "{\"direction\":\"up\"}"
```

### 5. Access History for Debugging

When investigating issues, get full history:
```typescript
Tool: mcp__validator__get_state_history
Parameters:
  match_id: "match-id"
```

### 6. Preserve State for Bug Reports

Save history to fixture files for reproduction:
```bash
# From game client state inspector
pbpaste | pnpm tsx scripts/save-history.ts
```

### 7. Load Fixtures for Testing

Test against known states:
```bash
curl -X POST http://localhost:5555/api/match/init-from-history \
  -H "Content-Type: application/json" \
  -d '{
    "history_file_id": "fixture-id",
    "player_id": "test-player",
    "signature": "test-sig"
  }'
```

## Troubleshooting

### Validator Won't Start

**Port already in use:**
```bash
lsof -i :5555
kill <PID>
```

**Dependencies not installed:**
```bash
cd validator/src/validator && bun install
```

**TypeScript errors:**
```bash
cd validator/src/validator && bun run type-check
```

### MCP Tools Not Working

**Check MCP server:**
```bash
curl http://localhost:5555/health
```

**Verify connection in Claude Code:**
Check MCP configuration includes validator server

**Restart MCP server:**
Restart validator to reinitialize MCP endpoint

### State Desync Issues

**Get current state:**
```typescript
Tool: mcp__validator__get_match_state
```

**Compare hashes:**
Check client hash vs validator computed_hash

**Review history:**
```typescript
Tool: mcp__validator__get_state_history
```

Find where divergence occurred

### Match Not Found

**List active matches:**
```typescript
Tool: mcp__validator__list_matches
```

**Match may have expired:**
Check created_at and last_action_at timestamps

**Clear and restart:**
```typescript
Tool: mcp__validator__clear_match   // then re-init from the game or test script
```

## Performance Considerations

### Memory Usage

- State history grows with moveIndex
- Each state snapshot includes full game state
- Consider clearing old matches periodically

### Hot Reload

- Bun watch mode reloads on file changes
- State is lost on reload
- Save important states to fixtures before code changes

### Concurrent Matches

- Validator can handle multiple matches simultaneously
- Each match has independent state and RNG
- Use match_id to isolate operations

## Development Workflow

### Typical Flow

1. Start validator with watcher
   ```bash
   cd validator/src/validator && bun run dev
   ```

2. Initialize a match (from the game: press V; or headless:
   `godot --headless --path game --script res://tools/test_validator_client.gd`)

3. Play game and monitor state
   ```typescript
   Tool: mcp__validator__list_matches
   Tool: mcp__validator__get_match_state
   ```

4. Debug issues with history
   ```typescript
   Tool: mcp__validator__get_state_history
   ```

5. Simulate proposed fixes
   ```typescript
   Tool: mcp__validator__simulate_action
   ```

6. Save interesting states
   ```bash
   # From game client
   pbpaste | pnpm tsx scripts/save-history.ts
   ```

7. Clean up when done
   ```typescript
   Tool: mcp__validator__clear_match
   ```

See `examples.md` for detailed workflow examples.
