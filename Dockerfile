# --- STAGE 1: Builder ---
FROM rockylinux:9 AS builder

# Install PostgreSQL 17, PostGIS 3.5, and TimescaleDB repos
RUN dnf install -y epel-release && \
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y https://packagecloud.io/install/repositories/timescale/timescaledb/config_file.repo?os=el&dist=9

# Install binaries and dev tools
RUN dnf install -y \
    postgresql17-server \
    postgresql17-devel \
    postgis35_17 \
    timescaledb-2-postgresql-17 \
    timescaledb-tools \
    gcc make cmake

# Initialize a temporary DB to generate and tune config
USER postgres
RUN /usr/pgsql-17/bin/initdb -D /tmp/data && \
    /usr/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf

# --- STAGE 2: Hardened Final Image ---
FROM rockylinux:9-minimal

# Setup postgres user (UID 26 is standard for PG on RHEL/Rocky)
RUN microdnf install -y shadow-utils && \
    groupadd -g 26 postgres && \
    useradd -u 26 -g postgres -d /var/lib/pgsql -s /bin/bash postgres

# Copy binaries and the tuned configuration
COPY --from=builder /usr/pgsql-17/ /usr/pgsql-17/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/postgresql.conf /var/lib/pgsql/template_configs/postgresql.conf

# Runtime dependencies
RUN microdnf install -y libxml2 geos proj gdal-libs openssl glibc && \
    microdnf clean all

# Environment
ENV PGDATA=/var/lib/pgsql/17/data
ENV PATH=/usr/pgsql-17/bin:$PATH

USER postgres
WORKDIR /var/lib/pgsql

# Final Security Polish: Ensure no world-writable directories
RUN chmod 700 /var/lib/pgsql

EXPOSE 5432
CMD ["postgres", "-D", "/var/lib/pgsql/17/data"]