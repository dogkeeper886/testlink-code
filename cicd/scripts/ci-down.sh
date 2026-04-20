#!/bin/bash
# Tear down CI environment
set -e

# Logs/side-effects only — keep stdout clean for callers that capture it.
exec >&2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker-compose.ci.yml"

echo "=== Stopping TestLink CI Environment ==="
docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
echo "=== CI Environment Stopped ==="
