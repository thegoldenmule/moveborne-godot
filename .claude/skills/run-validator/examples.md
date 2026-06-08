# Run Validator Skill - Examples

This document provides practical examples of managing and interacting with the Moveborne validator server.

## Example 1: Starting the Validator

### User Request
"Start the validator server"

### Claude Workflow

1. Check if already running:
```
Tool: Bash
Command: lsof -i :5555
```

2. If running, report status. If not, start it:
```
Tool: Bash
Command: cd validator/src/validator && bun run dev
Run in background: true
```

3. Wait a moment for startup, then verify:
```
Tool: Bash
Command: sleep 2 && curl http://localhost:5555/health
```

4. Confirm to user: "Validator is now running on port 5555 with hot-reload enabled"

## Example 2: Checking Validator Status

### User Request
"Is the validator running?"

### Claude Workflow

1. Check port 5555:
```
Tool: Bash
Command: lsof -i :5555
```

2. Check MCP endpoint:
```
Tool: mcp__validator__list_matches
```

3. Report status:
   - If both succeed: "Validator is running and MCP interface is accessible"
   - If port used but MCP fails: "Validator process found but MCP not responding"
   - If neither: "Validator is not running"

## Example 3: Listing Active Matches

### User Request
"Show me all active matches"

### Claude Workflow

1. Get match list:
```
Tool: mcp__validator__list_matches
```

2. Format and present results:
   - Total match count
   - For each match:
     - Match ID
     - Player ID
     - Move index
     - Game status
     - Action count
     - Created time
     - Last activity

Example output:
```
Found 2 active matches:

1. Match: test-match-1234567890
   Player: test-player-1
   Status: ONGOING
   Move Index: 15
   Actions: 15
   Created: 2025-01-15T10:30:00Z
   Last Action: 2025-01-15T10:45:00Z

2. Match: test-match-9876543210
   Player: test-player-2
   Status: WON
   Move Index: 42
   Actions: 42
   Created: 2025-01-15T09:00:00Z
   Last Action: 2025-01-15T09:30:00Z
```

## Example 4: Inspecting Match State

### User Request
"Show me the current state of match test-match-1234567890"

### Claude Workflow

1. Get match state:
```
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "test-match-1234567890"
```

2. Analyze and report:
   - Game status
   - Score and shards
   - Player health/energy/armor
   - Hand size and deck count
   - Current turn and moveIndex
   - Computed hash
   - RNG indices

Example report:
```
Match State: test-match-1234567890

Game Status: ONGOING
Score: 450 | Shards: 12 | Combo: 3x

Player Stats:
- Health: 45/60
- Energy: 2/3
- Armor: 5

Resources:
- Hand: 3 cards
- Deck: 12 cards

Progress:
- Turn: 8
- Move Index: 15

Validation:
- Hash: a3f2b9c...
- RNG Monster: 142
- RNG Loot: 67
```

## Example 5: Debugging State History

### User Request
"Something went wrong at moveIndex 10 in match test-match-1234567890. Can you investigate?"

### Claude Workflow

1. Get full state history:
```
Tool: mcp__validator__get_state_history
Parameters:
  match_id: "test-match-1234567890"
```

2. Find states around moveIndex 10:
   - Extract state at moveIndex 9
   - Extract state at moveIndex 10
   - Extract state at moveIndex 11

3. Compare states:
   - Health changes
   - Energy changes
   - Score/shard deltas
   - Hand/deck changes
   - Hash progression
   - RNG index changes

4. Report findings:
```
State Progression Analysis:

Move 9 -> 10:
- Action: SWIPE up (inferred from RNG change)
- Health: 60 -> 45 (took 15 damage)
- Energy: 3 -> 3 (no change)
- Score: 400 -> 450 (+50 points)
- Hand: 3 -> 3 cards
- Hash: abc123... -> def456...
- RNG Monster: 140 -> 142 (+2, monster spawn)

Move 10 -> 11:
- Action: PLAY_CARD (inferred from hand change)
- Health: 45 -> 45 (no change)
- Energy: 3 -> 1 (-2, card cost)
- Score: 450 -> 500 (+50 points)
- Hand: 3 -> 2 cards (-1 played)
- Hash: def456... -> ghi789...

Analysis: Player took damage at move 10, possibly from moving
into a monster. Hash progression is consistent throughout.
```

## Example 6: Simulating an Action

### User Request
"Before I swipe up, can you check what will happen?"

### Claude Workflow

1. Get current match state to confirm moveIndex:
```
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "test-match-1234567890"
```

2. Simulate the swipe:
```
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "test-match-1234567890"
  action_type: "SWIPE"
  action_payload: "{\"direction\":\"up\"}"
```

3. Analyze and report results:
```
Simulation Result: SWIPE up

Success: Yes

Predicted Changes:
- Score: +50 (will increase from 450 to 500)
- Shards: +0 (no shard pickup)
- Current Hash: abc123...
- Next Hash: def456...
- RNG Monster: 142 -> 144 (+2 indices)
- RNG Loot: 67 -> 67 (no change)

The action appears safe and will gain 50 points.
```

## Example 7: Testing Card Play

### User Request
"Simulate playing card 0 at position (2, 3) in match test-match-1234567890"

### Claude Workflow

1. Simulate the card play:
```
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "test-match-1234567890"
  action_type: "PLAY_CARD"
  action_payload: "{\"cardIndex\":0,\"targetRow\":2,\"targetCol\":3}"
```

2. Check if simulation succeeded:
   - If `success: true`, show preview
   - If `success: false`, show error

3. Report results:
```
Simulation Result: PLAY_CARD

Success: Yes

Card: Index 0
Target: (2, 3)

Predicted Changes:
- Score: +100 (monster killed)
- Shards: +1 (shard dropped)
- Current Hash: abc123...
- Next Hash: xyz789...
- RNG Monster: 142 -> 143 (+1, loot roll)
- RNG Loot: 67 -> 68 (+1, loot determined)

The card will successfully hit the target and eliminate the monster.
```

## Example 8: Reproducing a Bug from Fixture

### User Request
"Load the hash-mismatch-debug fixture and investigate the issue"

### Claude Workflow

1. Initialize match from fixture:
```
Tool: Bash
Command: curl -X POST http://localhost:5555/api/match/init-from-history \
  -H "Content-Type: application/json" \
  -d '{
    "history_file_id": "hash-mismatch-debug",
    "player_id": "test-player",
    "signature": "test-sig"
  }'
```

2. Get the connection details from response, then list matches:
```
Tool: mcp__validator__list_matches
```

3. Find the newly created match ID and get its state history:
```
Tool: mcp__validator__get_state_history
Parameters:
  match_id: "test-match-1761943052238"
```

4. Analyze the loaded history:
   - Check all hashes for consistency
   - Look for unexpected jumps in RNG indices
   - Compare consecutive states for anomalies
   - Identify the problematic moveIndex

5. Report findings:
```
Bug Analysis: hash-mismatch-debug

Loaded: 15 historical states
Issue: Hash mismatch at moveIndex 8

State 7 (before):
- Hash: abc123...
- RNG Monster: 20
- RNG Loot: 15

State 8 (problematic):
- Hash: def456... (expected: ghi789...)
- RNG Monster: 22 (+2, expected)
- RNG Loot: 16 (+1, expected)
- Extra card drawn (4 in hand, expected 3)

Analysis: Auto-draw triggered but not accounted for in hash
computation. Card draw event modified state without updating
the deterministic hash calculation.
```

## Example 9: Comparing Client and Validator State

### User Request
"The client shows hash xyz123 but validator shows abc456 at moveIndex 12"

### Claude Workflow

1. Get validator's view:
```
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "test-match-1234567890"
```

2. Get specific historical state:
```
Tool: mcp__validator__get_state_history
Parameters:
  match_id: "test-match-1234567890"
```

3. Extract moveIndex 12 from history

4. Compare:
   - Validator hash vs client hash
   - RNG indices
   - Game state fields (health, energy, score, etc.)
   - Hand and deck contents

5. Report divergence:
```
State Divergence at moveIndex 12:

Validator State:
- Hash: abc456...
- Health: 45
- Energy: 2
- Hand: 3 cards
- RNG Monster: 142
- RNG Loot: 67

Client State (reported):
- Hash: xyz123...
- Health: 45 (matches)
- Energy: 2 (matches)
- Hand: 4 cards (MISMATCH!)
- RNG indices: unknown

Diagnosis: Client has extra card in hand. Possible causes:
1. Client drew card outside of normal flow
2. Card removal failed to execute
3. State synchronization missed a message

Recommendation: Check client logs for card draw events between
moveIndex 11 and 12.
```

## Example 10: Cleaning Up Test Matches

### User Request
"Clean up all test matches"

### Claude Workflow

1. List all matches:
```
Tool: mcp__validator__list_matches
```

2. For each match with "test" in match_id or player_id:
```
Tool: mcp__validator__clear_match
Parameters:
  match_id: "test-match-1234567890"
```

3. Verify cleanup:
```
Tool: mcp__validator__list_matches
```

4. Report:
```
Cleanup Complete:

Removed 3 test matches:
- test-match-1234567890
- test-match-9876543210
- test-match-1111111111

Remaining matches: 0
```

## Example 11: Starting from Specific moveIndex

### User Request
"Load the fixture but start from moveIndex 10"

### Claude Workflow

1. Initialize with start_from_index:
```
Tool: Bash
Command: curl -X POST http://localhost:5555/api/match/init-from-history \
  -H "Content-Type: application/json" \
  -d '{
    "history_file_id": "hash-mismatch-debug",
    "start_from_index": 10,
    "player_id": "test-player",
    "signature": "test-sig"
  }'
```

2. Verify the starting state:
```
Tool: mcp__validator__list_matches
```

3. Get state to confirm:
```
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "<match_id_from_response>"
```

4. Report:
```
Fixture Loaded: hash-mismatch-debug

Starting Point:
- moveIndex: 10
- Score: 450
- Health: 45/60
- Available history: moveIndex 0-10

You can now play forward from this point or review the
history leading up to it.
```

## Example 12: Validating RNG Determinism

### User Request
"Check if the RNG is deterministic by simulating the same action twice"

### Claude Workflow

1. Get current state:
```
Tool: mcp__validator__get_match_state
Parameters:
  match_id: "test-match-1234567890"
```

2. Record current RNG indices

3. Simulate action first time:
```
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "test-match-1234567890"
  action_type: "SWIPE"
  action_payload: "{\"direction\":\"up\"}"
```

4. Record predicted next indices and hash

5. Simulate action second time:
```
Tool: mcp__validator__simulate_action
Parameters:
  match_id: "test-match-1234567890"
  action_type: "SWIPE"
  action_payload: "{\"direction\":\"up\"}"
```

6. Compare results:
```
RNG Determinism Test:

Initial State:
- RNG Monster: 142
- RNG Loot: 67
- Hash: abc123...

Simulation 1:
- Next RNG Monster: 144
- Next RNG Loot: 68
- Next Hash: def456...

Simulation 2:
- Next RNG Monster: 144 (MATCH ✓)
- Next RNG Loot: 68 (MATCH ✓)
- Next Hash: def456... (MATCH ✓)

Result: RNG is deterministic. Same input produces same output.
```

## Common Workflows

### Development Workflow

1. Start validator
2. Load game in browser
3. Play and test features
4. Check validator state after key actions
5. Simulate risky moves before executing
6. Clean up test matches when done

### Bug Investigation Workflow

1. Reproduce bug in game
2. Copy state history from game
3. Save to fixture file
4. Load fixture in validator
5. Get state history
6. Compare states around problematic moveIndex
7. Identify divergence point
8. Simulate actions to test fix hypothesis

### Testing Workflow

1. Start validator
2. Initialize match (from fixture or new)
3. For each test case:
   a. Simulate action
   b. Verify predicted outcome
   c. Execute if safe
   d. Compare actual vs predicted
4. Clean up when done

### State Analysis Workflow

1. List active matches
2. Get match state
3. Get state history
4. Export interesting states
5. Compare with client state
6. Identify discrepancies

## Tips for Effective Validator Use

1. **Always check before starting** - Avoid port conflicts
2. **Use simulation liberally** - Preview actions before executing
3. **Save interesting states** - Create fixtures for regression testing
4. **Clean up regularly** - Remove old test matches to free memory
5. **Check history first** - Before asking "what happened", get_state_history
6. **Compare hashes** - Hash mismatch indicates state divergence
7. **Monitor RNG indices** - Unexpected jumps indicate missing/extra operations
8. **Start from fixtures** - Reproduce issues with saved states
9. **Use hot-reload** - Let watcher handle code changes
10. **Verify cleanup** - list_matches after clearing to confirm

## Troubleshooting Scenarios

### Scenario: "Validator not responding"

1. Check if running: `lsof -i :5555`
2. Check logs: View terminal where validator is running
3. Try health endpoint: `curl http://localhost:5555/health`
4. Restart if needed: Stop and start scripts

### Scenario: "Hash mismatch on every action"

1. Get state history: `mcp__validator__get_state_history`
2. Find first mismatch moveIndex
3. Compare state before/after
4. Check RNG index progression
5. Look for missing state updates

### Scenario: "Match not found"

1. List matches: `mcp__validator__list_matches`
2. Check match ID spelling
3. Verify match wasn't cleared
4. Check if validator restarted (state lost)

### Scenario: "Simulation fails but action should be valid"

1. Get current state: `mcp__validator__get_match_state`
2. Verify moveIndex matches client
3. Check action payload format
4. Review error message from simulation
5. Compare with similar successful action
