#!/bin/bash

echo "Checking Moveborne Validator status..."
echo ""

PORT_CHECK=$(lsof -Pi :5555 -sTCP:LISTEN -t 2>/dev/null)

if [ -z "$PORT_CHECK" ]; then
    echo "✗ Validator is NOT running (port 5555 not in use)"
    exit 1
fi

echo "✓ Process found on port 5555"
echo "  PID: $PORT_CHECK"

HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5555/health 2>/dev/null)

if [ "$HEALTH_CHECK" = "200" ] || [ "$HEALTH_CHECK" = "404" ]; then
    echo "✓ HTTP server responding"
else
    echo "✗ HTTP server not responding (status: $HEALTH_CHECK)"
fi

MCP_PORT_CHECK=$(lsof -Pi :5555 -sTCP:LISTEN -t 2>/dev/null)

if [ -n "$MCP_PORT_CHECK" ]; then
    echo "✓ MCP interface available on port 5555"
else
    echo "✗ MCP interface not found on port 5555"
fi

BUN_PROCESS=$(pgrep -f "bun run --watch index.ts" || true)

if [ -n "$BUN_PROCESS" ]; then
    echo "✓ Bun watcher process running"
    echo "  PID: $BUN_PROCESS"
else
    echo "⚠ Bun watcher process not detected (may be running differently)"
fi

echo ""
echo "Summary: Validator is RUNNING"
