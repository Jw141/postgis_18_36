Here is your original `README.md` updated with information on how **`pg_cron`** works in this image, including how to use it with your custom user, its security implications, and how to troubleshoot it.

---

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

* **POSTGRES_USER:** The administrative superuser (The default 'postgres' user is locked).
* **POSTGRES_PASSWORD:** The password for your custom user.

### OPTIONAL

* **POSTGRES_DB:** Database to create (Defaults to `POSTGRES_USER`).
* **PGDATA:** Path for data storage (Default: `/var/lib/pgsql/18/data`).

### RASTER (For GeoServer / ImageMosaic)

* **POSTGIS_ENABLE_OUTDB_RASTERS:** Set to 'true' to allow external file access.
* **POSTGIS_GDAL_ENABLED_DRIVERS:** Set to 'ENABLE_ALL' for full format support.

---

## 3. KEY SECURITY FEATURES

### Identity Handover

On the first boot, the script creates your custom user as a `SUPERUSER` and immediately locks the 'postgres' user (`NOLOGIN`). This minimizes the attack surface.

### Password Sync

This image automatically syncs the database password with the `POSTGRES_PASSWORD` environment variable on every restart. If you rotate secrets in your environment, the DB updates automatically.

### Hardened Configuration

* **SCRAM-SHA-256:** The modern encryption standard enforced for all passwords.
* **Network Secure:** `listen_addresses` is set to '*' by default with strict HBA rules.
* **Auto-Permissions:** Automatically enforces strict `0700` permissions on the data volume.

### Native Background Scheduling (`pg_cron`)

The `pg_cron` extension is pre-installed and pre-loaded inside `shared_preload_libraries`. Because it runs directly inside the database server as a background worker thread, it eliminates the need to expose an external network port or use OS-level crontabs to automate database maintenance, partition updates, or cleanup routines.

---

## 4. USING PG_CRON

By default, `pg_cron` keeps its metadata and scheduling tables inside a database named `postgres`.

### Initializing the Extension

To use `pg_cron`, you must connect to your database using your custom administrative user and create the extension:

```sql
-- Connect to your primary database and run:
CREATE EXTENSION pg_cron;

```

### Scheduling a Task

Tasks are scheduled using standard cron syntax. For example, to run a TimescaleDB compression policy or vacuum a specific table every night at midnight:

```sql
SELECT cron.schedule('nightly-vacuum', '0 0 * * *', 'VACUUM ANALYZE my_spatial_table;');

```

---

## 5. DIRECTORY STRUCTURE

* `/var/lib/pgsql/18/data`: Active database storage.
* `/var/lib/pgsql/18/template_data`: Read-only "baked" config (used to seed new volumes, contains optimization configurations for TimescaleDB and `pg_cron`).
* `/docker-entrypoint-initdb.d/`: Place custom `.sql` or `.sh` scripts here to run on first boot.

---

## 6. TROUBLESHOOTING

* **Connecting as 'postgres':** This will fail by design. Always use your custom user (`POSTGRES_USER`).
* **`pg_cron` Permission Denied:** By default, `pg_cron` tasks run with the privileges of the user who scheduled them. Ensure your custom user has the correct object permissions before scheduling background SQL statements.
* **GeoServer Issues:** Ensure `POSTGIS_ENABLE_OUTDB_RASTERS=true` is set if using mosaics.
* **Locale:** System is pre-configured for `en_US.UTF-8` / `UTF8`.