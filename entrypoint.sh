#!/bin/bash
set -e

SETUP_FLAG="/var/lib/pgsql/18/data/.setup_complete"
TARGET_DB="${POSTGRES_DB:-$POSTGRES_USER}"

if [ ! -f "$SETUP_FLAG" ] && [ -n "$POSTGRES_USER" ]; then
    echo "First boot: Provisioning user '$POSTGRES_USER'..."

    # Start temporary local-only server
    postgres -D /var/lib/pgsql/18/data -c "listen_addresses=localhost" -c "logging_collector=off" &
    pid="$!"

    until pg_isready -q; do sleep 1; done

    # 1. THE HANDOVER: Create the new boss and lock the old one immediately
    psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
      CREATE USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
      CREATE DATABASE "$TARGET_DB" OWNER "$POSTGRES_USER";
      
      -- Kill the ladder we climbed up on
      ALTER USER postgres WITH NOLOGIN PASSWORD NULL;
EOSQL

    # 2. THE SETUP: Do everything else using the new user
    # This proves the new user has full control
    echo "Configuring extensions as $POSTGRES_USER..."
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$TARGET_DB" <<-EOSQL
      CREATE EXTENSION IF NOT EXISTS postgis;
      CREATE EXTENSION IF NOT EXISTS timescaledb;
EOSQL

    # 3. THE CUSTOM SCRIPTS: Run environment-specific logic
    if [ -d "/docker-entrypoint-initdb.d/" ]; then
        echo "Running initialization scripts as $POSTGRES_USER..."
        for f in /docker-entrypoint-initdb.d/*; do
            case "$f" in
                *.sql) echo "Executing $f"; psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$TARGET_DB" -f "$f" ;;
                *.sh)  echo "Executing $f"; . "$f" ;;
            esac
        done
    fi

    kill -s TERM "$pid"
    wait "$pid"
    
    touch "$SETUP_FLAG"
    echo "Hardened initialization complete. Role 'postgres' is disabled."
fi

exec "$@"