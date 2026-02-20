# --- STAGE 1: Builder ---
FROM docker.io/rockylinux/rockylinux:9.7 AS builder

# 1. Install system utilities, EPEL, and Go 1.25
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y golang-1.25.7 git gcc make cmake openssl-devel

# 2. Clone and Build timescaledb-tools 0.14.3
WORKDIR /build
RUN git clone --depth 1 --branch 0.14.3 https://github.com/timescale/timescaledb-tools.git && \
    cd timescaledb-tools && \
    make

# 3. Install official PostgreSQL 18 Repo and binaries
RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y postgresql18-server postgresql18-devel postgis36_18

# 4. Initialize and Tune using the freshly built tools
USER postgres
RUN /usr/pgsql-18/bin/initdb -D /tmp/data && \
    PATH=$PATH:/usr/pgsql-18/bin /build/timescaledb-tools/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf

# --- STAGE 2: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7-minimal

RUN microdnf install -y shadow-utils && \
    groupadd -g 26 postgres && \
    useradd -u 26 -g postgres -d /var/lib/pgsql -s /bin/bash postgres

# Copy only the compiled binaries (Now built with Go 1.25.7)
COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /build/timescaledb-tools/bin/timescaledb-tune /usr/bin/
COPY --from=builder /build/timescaledb-tools/bin/timescaledb-parallel-copy /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/postgresql.conf /var/lib/pgsql/template_configs/postgresql.conf

# Runtime dependencies
RUN microdnf install -y libxml2 geos proj gdal-libs openssl glibc && \
    microdnf clean all

ENV PATH=/usr/pgsql-18/bin:$PATH
USER postgres
WORKDIR /var/lib/pgsql
RUN mkdir -p /var/lib/pgsql/18/data && chmod 700 /var/lib/pgsql/18/data

EXPOSE 5432
CMD ["postgres", "-D", "/var/lib/pgsql/18/data"]