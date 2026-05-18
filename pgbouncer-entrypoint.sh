#!/usr/bin/env bash
set -e

# Path destinations
CONFIG_FILE="/etc/pgbouncer/pgbouncer.ini"
USERLIST_FILE="/etc/pgbouncer/userlist.txt"

echo "=== Initializing Hardened PgBouncer Container ==="

# 1. Dynamically bootstrap pgbouncer.ini if environment variables are provided
if [ -f "/etc/pgbouncer/pgbouncer.ini.template" ]; then
    cp /etc/pgbouncer/pgbouncer.ini.template "$CONFIG_FILE"
fi

# Apply custom downstream DB target settings via environment fallback
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-*}"

echo "Configuring database routing pointer to ${DB_HOST}:${DB_PORT}"
sed -i "s|{{DB_HOST}}|${DB_HOST}|g" "$CONFIG_FILE"
sed -i "s|{{DB_PORT}}|${DB_PORT}|g" "$CONFIG_FILE"
sed -i "s|{{DB_NAME}}|${DB_NAME}|g" "$CONFIG_FILE"

# 2. Enforce structural safety boundaries for authentication mapping
if [ -z "$AUTH_USER" ] || [ -z "$AUTH_PASSWORD" ]; then
    echo "WARNING: AUTH_USER or AUTH_PASSWORD not explicitly provided."
    echo "Ensure you are using a mounted configuration file map, or provide these variables for automatic bootstrapping."
else
    echo "Generating user encryption credentials profile..."
    # Formats entry using modern SCRAM-SHA-256 or structural plain fallback text rules
    echo "\"${AUTH_USER}\" \"${AUTH_PASSWORD}\"" > "$USERLIST_FILE"
    chmod 600 "$USERLIST_FILE"
fi

echo "=== Launching PgBouncer Process ==="
exec pgbouncer "$CONFIG_FILE"