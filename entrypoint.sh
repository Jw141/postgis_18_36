#!/bin/bash
set -e

: "${PGDATA:=/var/lib/pgsql/18/data}"
SETUP_FLAG="$PGDATA/.setup_complete"
TEMPLATE_DATA="/var/lib/pgsql/18/template_data"
TARGET_DB="${POSTGRES_DB:-$POSTGRES_USER}"

# 1. PVC INITIALIZATION
# If PGDATA is empty (like a new PVC), seed it from the hardened template
if [ ! -d "$PGDATA" ] || [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    echo "Initializing fresh volume from hardened template..."
    mkdir -p "$PGDATA"
    cp -rp "$TEMPLATE_DATA/." "$PGDATA/"
fi

# 2. RUNTIME PROVISIONING
if [ ! -f "$SETUP_FLAG" ] && [ -n "$POSTGRES_USER" ]; then
    echo "First boot: Configuring network and identity for $POSTGRES_USER..."

    # Configure network access (for SQLAlchemy/Remote tools)
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PGDATA/postgresql.conf"
    if ! grep -q "0.0.0.0/0" "$PGDATA/pg_hba.conf"; then
      echo "host all all 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
    fi

    # Start temp server for setup
    postgres -D "$PGDATA" -c "listen_addresses=localhost" -c "logging_collector=off" &
    pid="$!"
    until pg_isready -q; do sleep 1; done

    # Create the New Superuser and kill the 'postgres' role
    psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
      CREATE USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
      CREATE DATABASE "$TARGET_DB" OWNER "$POSTGRES_USER";
      ALTER USER postgres WITH NOLOGIN PASSWORD NULL;
EOSQL

    # Enable Extensions (as the new user)
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$TARGET_DB" -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS timescaledb;"

    # Run any environment-specific scripts
    if [ -d "/docker-entrypoint-initdb.d/" ]; then
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
fi

# 3. EXECUTE PRODUCTION SERVER
echo "Starting PostgreSQL..."
exec postgres -D "$PGDATA" "$@"