#!/bin/bash
# Start CI environment: build image, start services, init DB, verify health
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker-compose.ci.yml"

echo "=== Starting TestLink CI Environment ==="

echo "Building Docker image..."
docker compose -f "$COMPOSE_FILE" build

echo "Starting services..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for app to be healthy..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:8090/login.php > /dev/null 2>&1; then
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
docker compose -f "$COMPOSE_FILE" exec -T app bash /var/www/html/cicd/scripts/init-db.sh

echo "=== CI Environment Ready ==="
echo "TestLink URL: http://localhost:8090"
echo "Admin user: admin / admin"
echo "API key: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
