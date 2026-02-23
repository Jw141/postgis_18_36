# --- STAGE 1: Builder ---
FROM docker.io/rockylinux/rockylinux:9.7 AS builder

# 1. Install system utilities, EPEL, and Go
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --allowerasing golang git gcc make cmake openssl-devel curl tar

# 2. Build only the Tuner (The safe, non-vulnerable binary)
RUN GOPROXY=https://proxy.golang.org,direct \
    go install github.com/timescale/timescaledb-tune/cmd/timescaledb-tune@latest && \
    cp /root/go/bin/timescaledb-tune /usr/bin/

# 3. Install official PostgreSQL 18 Repo and binaries
RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y postgresql18-server postgresql18-devel postgis36_18 timescaledb_18

# 4. Initialize and Tune
RUN mkdir -p /tmp/data && chown postgres:postgres /tmp/data
RUN mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql
USER postgres
RUN /usr/pgsql-18/bin/initdb -D /tmp/data && \
    PATH=$PATH:/usr/pgsql-18/bin /usr/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf

# --- STAGE 2: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7-minimal

# Update all base packages to clear OS vulnerabilities
RUN microdnf update -y && microdnf install -y shadow-utils

# Setup postgres user
RUN groupadd -g 26 postgres && \
    useradd -u 26 -g postgres -d /var/lib/pgsql -s /bin/bash postgres

# CREATE THE SOCKET DIRECTORY HERE (Crucial for psql)
RUN mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql && chmod 775 /run/postgresql

# Runtime dependencies for PostGIS/Postgres
RUN microdnf install -y \
    libxml2 \
    geos \
    proj \
    gdal-libs \
    openssl \
    glibc \
    numactl-libs \
    libicu \
    liburing \
    lz4 \
    zstd \
    krb5-libs \
    openldap \
    systemd-libs && \
    microdnf clean all

# Copy binaries from builder
COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/ /var/lib/pgsql/18/data/

ENV PATH=/usr/pgsql-18/bin:$PATH
USER postgres
WORKDIR /var/lib/pgsql

# Set permissions (important for security)
RUN chmod 700 /var/lib/pgsql/18/data

EXPOSE 5432

CMD ["postgres", "-D", "/var/lib/pgsql/18/data", \
     "-c", "listen_addresses=*", \
     "-c", "logging_collector=off"]