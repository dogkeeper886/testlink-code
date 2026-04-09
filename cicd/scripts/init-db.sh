#!/bin/bash
# Initialize TestLink database schema for CI
# Runs inside the app container against the CI PostgreSQL instance
set -e

DB_HOST="${DB_HOST:-db}"
DB_USER="${DB_USER:-testlink}"
DB_PASS="${DB_PASS:-testlink}"
DB_NAME="${DB_NAME:-testlink}"

export PGPASSWORD="$DB_PASS"

echo "Waiting for PostgreSQL..."
for i in $(seq 1 30); do
  if pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null; then
    echo "PostgreSQL is ready."
    break
  fi
  sleep 1
done

SQL_DIR="/var/www/html/install/sql/postgres"

echo "Creating tables..."
sed 's|/\*prefix\*/||g' "$SQL_DIR/testlink_create_tables.sql" | \
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -q

echo "Creating UDFs..."
sed 's|/\*prefix\*/||g' "$SQL_DIR/testlink_create_udf0.sql" | \
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -q

echo "Inserting default data..."
sed 's|/\*prefix\*/||g' "$SQL_DIR/testlink_create_default_data.sql" | \
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -q

# Generate an API key for the admin user (user_id=1)
# The key is a known value so test cases can use it
API_KEY="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
echo "Setting admin API key..."
psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -q -c \
  "UPDATE users SET script_key='$API_KEY' WHERE id=1;"

echo "Database initialized successfully."
echo "Admin API key: $API_KEY"
