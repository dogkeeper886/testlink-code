#!/bin/bash
# Start CI environment: build image, start services, init DB, verify health
set -e

# This script's output is entirely log/side-effect — no data. Send it
# all to stderr so a caller that captures the wrapper's stdout (e.g.
# `run-tests.sh ... --format json > results.json`) doesn't end up
# with docker build output and banner lines interleaved with JSON.
exec >&2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker-compose.ci.yml"

# Allow direct invocation (outside run-tests.sh) to still pick up .env values.
ENV_FILE="$SCRIPT_DIR/../tests/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

TL_URL="${TL_URL:-http://localhost:${TL_PORT:-8091}}"

echo "=== Starting TestLink CI Environment ==="

echo "Building Docker image..."
docker compose -f "$COMPOSE_FILE" build

echo "Starting services..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for app to be healthy..."
for i in $(seq 1 60); do
  if curl -sf "$TL_URL/login.php" > /dev/null 2>&1; then
    echo "App is responding."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Timeout waiting for app."
    docker compose -f "$COMPOSE_FILE" logs app
    exit 1
  fi
  sleep 2
done

echo "Initializing database..."
# Forward TL_DEV_KEY into the container so init-db.sh seeds the matching
# admin key. Falls back to the script's own default if the env var is unset.
docker compose -f "$COMPOSE_FILE" exec -T -e "TL_DEV_KEY=${TL_DEV_KEY:-}" app \
  bash /var/www/html/cicd/scripts/init-db.sh

echo "=== CI Environment Ready ==="
echo "TestLink URL: $TL_URL"
echo "Admin user: admin / admin"
echo "API key: ${TL_DEV_KEY:-a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4}"
