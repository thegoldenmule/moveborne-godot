#!/bin/bash

echo "Starting Moveborne Validator..."

if lsof -Pi :5555 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Error: Port 5555 is already in use"
    echo "Run stop-validator.sh to stop the existing process"
    exit 1
fi

cd "$(dirname "$0")/../../../../validator/src/validator" || exit 1

echo "Starting validator with Bun watcher..."
PORT=5555 bun run dev &

VALIDATOR_PID=$!

sleep 2

if lsof -Pi :5555 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ Validator started successfully on port 5555"
    echo "✓ MCP interface available at http://localhost:5555/mcp"
    echo "✓ Process ID: $VALIDATOR_PID"
    echo ""
    echo "The validator is running with hot-reload enabled."
    echo "To stop: .claude/skills/run-validator/scripts/stop-validator.sh"
else
    echo "✗ Failed to start validator"
    exit 1
fi
