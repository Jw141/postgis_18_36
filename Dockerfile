# --- STAGE 1: Builder ---
FROM docker.io/rockylinux/rockylinux:9.7 AS builder

RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --allowerasing golang git gcc make cmake openssl-devel curl tar glibc-langpack-en

RUN GOPROXY=https://proxy.golang.org,direct \
    go install github.com/timescale/timescaledb-tune/cmd/timescaledb-tune@latest && \
    cp /root/go/bin/timescaledb-tune /usr/bin/

RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y postgresql18-server postgresql18-devel postgis36_18 timescaledb_18

RUN mkdir -p /tmp/data /run/postgresql && chown postgres:postgres /tmp/data /run/postgresql
USER postgres
# Added locale flags for UTF8 consistency
RUN /usr/pgsql-18/bin/initdb -D /tmp/data --locale=en_US.UTF-8 --encoding=UTF8 && \
    PATH=$PATH:/usr/pgsql-18/bin /usr/bin/timescaledb-tune --quiet --yes --conf-path=/tmp/data/postgresql.conf

# --- STAGE 2: Hardened Final Image ---
FROM docker.io/rockylinux/rockylinux:9.7

RUN dnf clean all && \
    dnf update -y --refresh && \
    dnf install -y epel-release https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf config-manager --set-enabled crb

RUN dnf install -y --allowerasing \
    shadow-utils \
    postgresql18-server \
    postgis36_18 \
    timescaledb_18 \
    glibc-langpack-en && \
    dnf clean all

RUN mkdir -p /run/postgresql /docker-entrypoint-initdb.d /var/lib/pgsql/18/template_data && \
    chown -R postgres:postgres /run/postgresql /docker-entrypoint-initdb.d /var/lib/pgsql

# Documentation (Done as root before switching users)
COPY README.md /usr/local/share/doc/spatial-db-readme.md
RUN echo "alias image-info='cat /usr/local/share/doc/spatial-db-readme.md'" >> /etc/bash.bashrc

COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/ /var/lib/pgsql/18/template_data/

COPY --chown=postgres:postgres entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PATH=/usr/pgsql-18/bin:$PATH \
    PGDATA=/var/lib/pgsql/18/data \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Metadata
LABEL org.opencontainers.image.description="Hardened PG18/PostGIS image. Features: locked 'postgres' user, SCRAM auth, automatic password sync, and GeoServer raster support."

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD pg_isready -U "${POSTGRES_USER:-postgres}" || exit 1

USER postgres
WORKDIR /var/lib/pgsql

EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["-c", "logging_collector=off"]