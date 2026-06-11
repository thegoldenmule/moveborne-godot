# Moveborne Validator Service

A high-performance real-time validation service for the Moveborne TCG platform, built with Bun, Hono, and gRPC (reached in production through the Snapser Hermes WebSocket; protos in `../../protos/`).

## Quick Start

```bash
# Install dependencies
bun install

# Run development server (with hot reload)
bun run dev

# Run production server
bun run start

# Type check
bun run type-check
```

## What is This?

The Validator service provides real-time validation for:
- Game moves and actions
- State consistency verification
- Player action legality

## Architecture

This service uses:
- **[Bun](https://bun.sh/)** - Fast JavaScript runtime (3-4x faster than Node.js)
- **[Hono](https://hono.dev/)** - Lightweight web framework (health/status/history/MCP routes)
- **[@grpc/grpc-js](https://www.npmjs.com/package/@grpc/grpc-js)** - the game-facing
  `moveborne.validator.v1.ValidatorService` (InitMatch / ValidateAction / CompleteMatch)
- **[protobufjs](https://www.npmjs.com/package/protobufjs)** - runtime proto loading + the
  Hermes ClientMessage/ServerMessage envelope served at `/hermes/ws` (local emulation of the
  Snapser Hermes WSS endpoint, so the game client has one codepath)

Transports: gRPC on `GRPC_PORT` (Hermes proxies to it in the snapend), the Hermes-emulation
WebSocket and HTTP on `PORT`. The transport-agnostic handlers live in `service.ts`.

## Configuration

### Environment Setup

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Update `.env` with your configuration (especially `VALIDATOR_SHARED_SECRET` for production)

### Environment Variables

- `VALIDATOR_SHARED_SECRET` - **Required**. Shared secret for signing validator responses. Must be kept secure.
  - For development: Use the provided default in `.env`
  - For production: Generate a strong secret with `openssl rand -hex 32`

- `GRPC_PORT` - Optional. gRPC ValidatorService port (default: 8081)

- `MATCH_SESSION_TTL` - Optional. Match session time-to-live in seconds (default: 3600)
  - How long match state is retained after the last action

- `PORT` - Optional. Server port (default: 3000)

## Project Structure

```
.
├── index.ts           # Main application entry point
├── package.json       # Dependencies and scripts
├── tsconfig.json      # TypeScript configuration
├── bun.lockb          # Bun lockfile
├── README.md          # This file
└── CLAUDE.md          # Agent instructions
```

## Development

The server runs with hot reload in development mode:

```bash
bun run dev
```

Any changes to `index.ts` will automatically restart the server.

## Documentation

- See the bundle root [`validator/README.md`](../../README.md) for setup in this repo.
- Agent usage is documented in `.claude/skills/run-validator/` (SKILL.md, reference.md, examples.md).

## Integration

The validator integrates with:
- **Client** - Real-time validation feedback

## Performance
