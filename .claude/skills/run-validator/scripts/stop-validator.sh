#!/bin/bash

echo "Stopping Moveborne Validator..."

PIDS=$(lsof -ti :5555)

if [ -z "$PIDS" ]; then
    echo "No validator process found on port 5555"
    exit 0
fi

echo "Found validator process(es): $PIDS"

for PID in $PIDS; do
    echo "Killing process $PID..."
    kill -9 "$PID" 2>/dev/null
done

BUN_PIDS=$(pgrep -f "bun run --watch index.ts" || true)
if [ -n "$BUN_PIDS" ]; then
    echo "Found Bun watcher process(es): $BUN_PIDS"
    for PID in $BUN_PIDS; do
        echo "Killing Bun process $PID..."
        kill -9 "$PID" 2>/dev/null
    done
fi

sleep 1

if lsof -Pi :5555 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✗ Warning: Validator may still be running on port 5555"
    echo "  Try manually: lsof -ti :5555 | xargs kill -9"
    exit 1
else
    echo "✓ Validator stopped successfully"
fi
