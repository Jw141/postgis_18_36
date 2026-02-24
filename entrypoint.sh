#!/bin/bash
set -e

: "${PGDATA:=/var/lib/pgsql/18/data}"
SETUP_FLAG="$PGDATA/.setup_complete"
TEMPLATE_DATA="/var/lib/pgsql/18/template_data"
TARGET_DB="${POSTGRES_DB:-$POSTGRES_USER}"

# 1. HELP COMMAND
if [ "$1" = 'help' ]; then
    echo "--------------------------------------------------------"
    echo " HARDENED POSTGIS & TIMESCALEDB IMAGE HELP"
    echo "--------------------------------------------------------"
    echo "REQUIRED ENV:"
    echo "  POSTGRES_USER      : Admin user (postgres is locked)"
    echo "  POSTGRES_PASSWORD  : Admin password (auto-syncs on boot)"
    echo ""
    echo "RASTER CONFIG:"
    echo "  POSTGIS_ENABLE_OUTDB_RASTERS=true"
    echo "  POSTGIS_GDAL_ENABLED_DRIVERS='GTiff PNG JPEG'"
    echo "--------------------------------------------------------"
    exit 0
fi

# 2. PVC INITIALIZATION (Seeding empty volumes)
if [ ! -d "$PGDATA" ] || [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    echo "Initializing fresh volume from hardened template..."
    mkdir -p "$PGDATA"
    cp -rp "$TEMPLATE_DATA/." "$PGDATA/"
fi

# 3. ENFORCE PERMISSIONS & NETWORK (Every Boot)
chmod 0700 "$PGDATA"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PGDATA/postgresql.conf"
if ! grep -q "0.0.0.0/0" "$PGDATA/pg_hba.conf"; then
  echo "host all all 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
fi

# 4. RUNTIME PROVISIONING (First Boot Only)
if [ ! -f "$SETUP_FLAG" ] && [ -n "$POSTGRES_USER" ]; then
    echo "First boot: Configuring identity and PostGIS Raster settings..."
    
    # Start temp server
    postgres -D "$PGDATA" -c "listen_addresses=localhost" -c "logging_collector=off" &
    pid="$!"
    until pg_isready -q; do sleep 1; done

    # Identity Swap & Database Creation
    psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
      CREATE USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
      CREATE DATABASE "$TARGET_DB" OWNER "$POSTGRES_USER";
      ALTER USER postgres WITH NOLOGIN PASSWORD NULL;
EOSQL

    # Enable Extensions & Configure Rasters in one block to avoid "Unknown Parameter" errors
    echo "PostGIS: Configuring Raster and GDAL settings..."
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$TARGET_DB" <<-EOSQL
      CREATE EXTENSION IF NOT EXISTS postgis;
      CREATE EXTENSION IF NOT EXISTS timescaledb;
EOSQL

    # Apply PostGIS Global Raster Settings if requested
    if [[ "$POSTGIS_ENABLE_OUTDB_RASTERS" =~ ^(true|1|on)$ ]]; then
        echo "PostGIS: Enabling Out-of-DB Rasters"
        psql -U "$POSTGRES_USER" -d "$TARGET_DB" -c "ALTER SYSTEM SET postgis.enable_outdb_rasters TO on;"
    fi

    if [ -n "$POSTGIS_GDAL_ENABLED_DRIVERS" ]; then
        echo "PostGIS: Enabling GDAL drivers: $POSTGIS_GDAL_ENABLED_DRIVERS"
        psql -U "$POSTGRES_USER" -d "$TARGET_DB" -c "ALTER SYSTEM SET postgis.gdal_enabled_drivers TO '$POSTGIS_GDAL_ENABLED_DRIVERS';"
    fi
    
    psql -U "$POSTGRES_USER" -d "$TARGET_DB" -c "SELECT pg_reload_conf();"

    # Run user-provided init scripts
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

# 5. PASSWORD SYNC (Every Boot)
if [ -f "$SETUP_FLAG" ] && [ -n "$POSTGRES_PASSWORD" ]; then
    echo "Syncing password for $POSTGRES_USER..."
    postgres -D "$PGDATA" -c "listen_addresses=localhost" -c "logging_collector=off" &
    sync_pid="$!"
    until pg_isready -q; do sleep 1; done
    
    psql -U "$POSTGRES_USER" -d "$TARGET_DB" -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$POSTGRES_PASSWORD';"
    
    kill -s TERM "$sync_pid"
    wait "$sync_pid"
fi

[Image of PostgreSQL entrypoint lifecycle showing initialization, configuration, and runtime]

echo "Starting PostgreSQL..."
exec postgres -D "$PGDATA" "$@"