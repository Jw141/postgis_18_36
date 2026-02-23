#!/bin/bash
set -e

# Path to our "Initialization" flag
SETUP_FLAG="/var/lib/pgsql/18/data/.setup_complete"

# 1. Run only on first boot
if [ ! -f "$SETUP_FLAG" ] && [ -n "$POSTGRES_USER" ]; then
    echo "First boot: Provisioning user '$POSTGRES_USER' and database '${POSTGRES_DB:-$POSTGRES_USER}'..."

    # Start Postgres temporarily
    postgres -D /var/lib/pgsql/18/data -c "listen_addresses=localhost" -c "logging_collector=off" &
    pid="$!"

    until pg_isready -q; do sleep 1; done

    # 2. CREATE the new user and database
    # 3. DISABLE the postgres user (NOLOGIN)
    psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
      -- 1. Create the new world
      CREATE USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
      CREATE DATABASE "${POSTGRES_DB:-$POSTGRES_USER}" OWNER "$POSTGRES_USER";
      
      -- 2. Connect to the new database BEFORE locking postgres
      \c "${POSTGRES_DB:-$POSTGRES_USER}"
      CREATE EXTENSION IF NOT EXISTS postgis;
      CREATE EXTENSION IF NOT EXISTS timescaledb;

      -- 3. FINALLY, lock the postgres user as the very last step
      \c postgres
      ALTER USER postgres WITH NOLOGIN PASSWORD NULL;
EOSQL

    kill -s TERM "$pid"
    wait "$pid"
    
    touch "$SETUP_FLAG"
    echo "Setup complete. User 'postgres' is now disabled for login."
fi

# 4. Hand over to the main process
exec "$@"