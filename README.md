# HARDENED POSTGIS & TIMESCALEDB (PG18)

Base Image: Rocky Linux 9.7 (Hardened)

## 1. QUICK START

To run the container with basic credentials:

```bash
docker run -d \
  --name spatial_db \
  -e POSTGRES_USER=jw141 \
  -e POSTGRES_PASSWORD=my_secure_password \
  -p 5432:5432 \
  -v pg_data:/var/lib/pgsql/18/data \
  my-hardened-image:latest

```

## 2. ENVIRONMENT VARIABLES

### REQUIRED

* POSTGRES_USER: The administrative superuser (The 'postgres' user is locked).
* POSTGRES_PASSWORD: The password for your custom user.

### OPTIONAL

* POSTGRES_DB: Database to create (Defaults to POSTGRES_USER).
* PGDATA: Path for data storage (Default: /var/lib/pgsql/18/data).

### RASTER (For GeoServer / ImageMosaic)

* POSTGIS_ENABLE_OUTDB_RASTERS: Set to 'true' to allow external file access.
* POSTGIS_GDAL_ENABLED_DRIVERS: Set to 'ENABLE_ALL' for full format support.

## 3. KEY SECURITY FEATURES

### Identity Handover

On the first boot, the script creates your custom user as a SUPERUSER and immediately locks the 'postgres' user (NOLOGIN). This minimizes the attack surface.

### Password Sync

This image automatically syncs the database password with the POSTGRES_PASSWORD environment variable on every restart. If you rotate secrets in your environment, the DB updates automatically.

### Hardened Configuration

* SCRAM-SHA-256: The modern encryption standard for all passwords.
* Network Secure: listen_addresses is set to '*' by default with strict HBA rules.
* Auto-Permissions: Automatically enforces 0700 permissions on the data volume.

## 4. DIRECTORY STRUCTURE

* /var/lib/pgsql/18/data: Active database storage.
* /var/lib/pgsql/18/template_data: Read-only "baked" config (used to seed new volumes).
* /docker-entrypoint-initdb.d/: Place custom .sql or .sh scripts here to run on first boot.

## 5. TROUBLESHOOTING

* Connecting as 'postgres': This will fail by design. Always use your custom user.
* GeoServer Issues: Ensure POSTGIS_ENABLE_OUTDB_RASTERS=true is set if using mosaics.
* Locale: System is pre-configured for en_US.UTF-8 / UTF8.
