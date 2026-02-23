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
FROM docker.io/rockylinux/rockylinux:9.7

# 1. Patch vulnerabilities and setup repos
RUN dnf clean all && \
    dnf update -y --refresh && \
    dnf install -y epel-release https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf config-manager --set-enabled crb

# 2. Install Runtimes (automates user creation and library dependencies)
RUN dnf install -y --allowerasing \
    shadow-utils \
    postgresql18-server \
    postgis36_18 \
    timescaledb_18 && \
    dnf clean all

# 3. Directories and Permissions
# We copy to /template_data so it doesn't get hidden by a volume mount
RUN mkdir -p /run/postgresql /docker-entrypoint-initdb.d /var/lib/pgsql/18/template_data && \
    chown -R postgres:postgres /run/postgresql /docker-entrypoint-initdb.d /var/lib/pgsql

# 4. Copy Assets
COPY --from=builder /usr/pgsql-18/ /usr/pgsql-18/
COPY --from=builder /usr/bin/timescaledb-tune /usr/bin/
COPY --from=builder --chown=postgres:postgres /tmp/data/ /var/lib/pgsql/18/template_data/

# 5. Environment and Entrypoint
COPY --chown=postgres:postgres entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PATH=/usr/pgsql-18/bin:$PATH
ENV PGDATA=/var/lib/pgsql/18/data
USER postgres
WORKDIR /var/lib/pgsql

EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# CMD is passed to the 'postgres' command inside entrypoint.sh
CMD ["-c", "logging_collector=off"]