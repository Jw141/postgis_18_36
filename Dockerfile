# --- STAGE 1: Builder ---
FROM docker.io/rockylinux/rockylinux:9.7 AS builder

# 1. Install system utilities, EPEL, and Go
# --allowerasing is critical here to swap curl-minimal for full curl
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --allowerasing golang git gcc make cmake openssl-devel curl tar

# 2. Build the tuner and parallel-copy from their specific repositories
RUN GOPROXY=https://proxy.golang.org,direct \
    go install github.com/timescale/timescaledb-tune/cmd/timescaledb-tune@latest && \
    GOPROXY=https://proxy.golang.org,direct \
    go install github.com/timescale/timescaledb-parallel-copy/cmd/timescaledb-parallel-copy@latest && \
    cp /root/go/bin/timescaledb-* /usr/bin/

# 3. Install official PostgreSQL 18 Repo and binaries
RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y postgresql18-server postgresql18-devel postgis36_18

# 4. Initialize and Tune
# We stay as root for a moment to set up the temp directory, then run as postgres
RUN mkdir -p /tmp/data && chown postgres:postgres /tmp/data
USER postgres
RUN /usr/pgsql-18/bin/initdb -D /tmp/data && \
    PATH=$PATH:/usr/pgsql-18/bin /usr/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf

# --- STAGE 2: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7-minimal

# Update all base packages to clear OS vulnerabilities
RUN microdnf update -y && microdnf install -y shadow-utils

# Setup postgres user (UID 26 is standard for Postgres)
RUN microdnf install -y shadow-utils && \
    groupadd -g 26 postgres && \
    useradd -u 26 -g postgres -d /var/lib/pgsql -s /bin/bash postgres

# Copy binaries from builder
COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder /usr/bin/timescaledb-parallel-copy /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/postgresql.conf /var/lib/pgsql/template_configs/postgresql.conf

# Runtime dependencies (Minimal set)
RUN microdnf install -y libxml2 geos proj gdal-libs openssl glibc && \
    microdnf clean all

ENV PATH=/usr/pgsql-18/bin:$PATH
USER postgres
WORKDIR /var/lib/pgsql
RUN mkdir -p /var/lib/pgsql/18/data && chmod 700 /var/lib/pgsql/18/data

EXPOSE 5432
CMD ["postgres", "-D", "/var/lib/pgsql/18/data"]