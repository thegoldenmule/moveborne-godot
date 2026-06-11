---
name: run-validator
description: Run and manage the Moveborne validator server with Bun watcher for hot-reload development. Includes tools for starting, stopping, and inspecting the validator using the MCP interface at localhost:5555/mcp. Use this skill when testing game logic, debugging state synchronization, validating actions, or inspecting match states. Provides MCP tools for listing matches, getting state, simulating actions, and accessing state history.
---

# Run Validator Skill

This skill enables Claude to manage the Moveborne validator server and interact with it through the MCP interface.

## When to Use

- Starting the validator server for development or testing
- Stopping or restarting the validator when needed
- Inspecting active matches and their states
- Debugging state synchronization issues
- Simulating game actions without applying them
- Validating game logic and mechanics
- Accessing state history for debugging
- Loading and replaying saved game states

## Prerequisites

1. Bun runtime installed (used instead of Node.js)
2. Validator dependencies installed (`bun install` in the `validator/` workspace root)
3. MCP server configured to connect to validator at `http://localhost:5555/mcp`

## Core Capabilities

### Server Management
- Start validator with hot-reload watcher
- Check if validator is running
- Stop validator process when needed
- Restart validator (stop and start)

### MCP Interface Tools
Access validator state and functionality through MCP:
- `mcp__validator__list_matches` - List all active matches
- `mcp__validator__get_match_state` - Get complete state for a match
- `mcp__validator__get_state_history` - Get full state history for debugging
- `mcp__validator__simulate_action` - Test actions without applying them
- `mcp__validator__clear_match` - Remove a match from the store

### State Inspection
Query and analyze match states:
- View active matches with metadata
- Get synchronized game state with hash validation
- Access complete state history for any match
- Compare states across moveIndex values
- Inspect RNG indices and deterministic behavior

### Action Simulation
Test game actions before executing:
- Simulate swipes (up, down, left, right)
- Simulate card plays
- Preview state changes and deltas
- Validate action legality
- Check hash consistency

### State Replay
Load and replay saved game states:
- Initialize matches from fixture files
- Load states from base64-encoded data
- Start from specific moveIndex
- Reproduce reported bugs
- Test edge cases with known states

## Quick Start

1. Use the `start-validator.sh` script to launch the validator with watcher
2. Verify it's running with `check-validator.sh` or by calling `mcp__validator__list_matches`
3. Use MCP tools to inspect and interact with match states
4. If restart needed, use `stop-validator.sh` then `start-validator.sh`

## Important Notes

- The validator runs with `bun run --watch` for automatic hot-reload on file changes
- Runs on port 5555 — HTTP, the Hermes-emulation WebSocket (`/hermes/ws`), and the MCP interface (`/mcp`) share it (the start script sets `PORT=5555`); the gRPC ValidatorService listens on 8081
- MCP server provides JSON-RPC interface for programmatic access
- State history is persisted in-memory per match session
- Validator uses deterministic RNG for reproducible game logic

## Integration

This skill integrates with:
- Bun runtime for server execution
- MCP protocol for tool access
- gRPC + the Hermes-envelope WebSocket (`/hermes/ws`) for real-time game validation
- State history replay system
- Game logic package (`@spyre-io/moveborne-logic`)

See `reference.md` for complete MCP API documentation and `examples.md` for common validator workflows.
