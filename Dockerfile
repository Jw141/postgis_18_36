# --- STAGE 1: Builder ---
FROM rockylinux:9 AS builder

# 1. Install system utilities and EPEL
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb

# 2. Install official PostgreSQL Repo
RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql

# 3. Add Timescale Repo using their official script
RUN curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.rpm.sh | bash

# 4. Clean metadata and install PG 18, PostGIS 3.6, and Timescale
# Note: Using '*' for PostGIS allows it to find the exact match for PG18
RUN dnf clean all && dnf install -y \
    postgresql18-server \
    postgresql18-devel \
    postgis36_18 \
    timescaledb-2-postgresql-18 \
    timescaledb-tools \
    gcc make cmake openssl-devel

# 5. Initialize a temp DB and tune it
USER postgres
RUN /usr/pgsql-18/bin/initdb -D /tmp/data && \
    PATH=$PATH:/usr/pgsql-18/bin /usr/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf
    
# --- STAGE 2: Hardened Final Image ---
FROM rockylinux:9-minimal

# Setup postgres user
RUN microdnf install -y shadow-utils && \
    groupadd -g 26 postgres && \
    useradd -u 26 -g postgres -d /var/lib/pgsql -s /bin/bash postgres

# Copy binaries and the tuned config
COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/postgresql.conf /var/lib/pgsql/template_configs/postgresql.conf

# Install bare minimum runtime libs for PostGIS (GDAL, GEOS, PROJ)
RUN microdnf install -y libxml2 geos proj gdal-libs openssl glibc && \
    microdnf clean all

# Environment
ENV PGDATA=/var/lib/pgsql/18/data
ENV PATH=/usr/pgsql-18/bin:$PATH

USER postgres
WORKDIR /var/lib/pgsql
RUN mkdir -p /var/lib/pgsql/18/data && chmod 700 /var/lib/pgsql/18/data

EXPOSE 5432
CMD ["postgres", "-D", "/var/lib/pgsql/18/data"]