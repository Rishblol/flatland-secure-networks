FROM debian:bookworm-slim AS workload
RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 util-linux \
    && rm -rf /var/lib/apt/lists/*
COPY --chmod=755 config/setup-routes.sh /usr/local/bin/flatland-setup-routes

FROM workload AS ssh-host
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
COPY --chmod=755 config/start-ssh.sh /usr/local/bin/flatland-start-ssh
COPY config/sshd_config /etc/ssh/flatland_sshd_config
RUN useradd --create-home --shell /bin/sh lab \
    && echo 'lab:flatland-ssh-demo' | chpasswd
ENTRYPOINT ["flatland-setup-routes", "flatland-start-ssh"]

FROM ssh-host AS workstation
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl netcat-openbsd smbclient sshpass \
    && rm -rf /var/lib/apt/lists/*
COPY fixtures/transfer.txt /fixtures/transfer.txt
CMD ["sleep", "infinity"]

FROM ssh-host AS web
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl nginx openssl \
    && rm -rf /var/lib/apt/lists/*
COPY config/nginx.conf /etc/nginx/flatland.conf
COPY --chmod=755 config/start-web.sh /usr/local/bin/flatland-start-web
COPY fixtures/index.html /srv/web/index.html
CMD ["flatland-start-web"]

FROM ssh-host AS app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl postgresql-client python3 \
    && rm -rf /var/lib/apt/lists/*
COPY fixtures/health /srv/app/health
CMD ["python3", "-m", "http.server", "8080", "--directory", "/srv/app"]

FROM postgres:17-bookworm AS database
RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 openssh-server util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
    && useradd --create-home --shell /bin/sh lab \
    && echo 'lab:flatland-ssh-demo' | chpasswd
COPY --chmod=755 config/start-ssh.sh /usr/local/bin/flatland-start-ssh
COPY --from=workload /usr/local/bin/flatland-setup-routes /usr/local/bin/flatland-setup-routes
COPY config/sshd_config /etc/ssh/flatland_sshd_config
COPY fixtures/database.sql /docker-entrypoint-initdb.d/10-flatland.sql
ENTRYPOINT ["flatland-setup-routes", "flatland-start-ssh", "docker-entrypoint.sh"]
CMD ["postgres"]

FROM ssh-host AS file
RUN apt-get update \
    && apt-get install -y --no-install-recommends samba smbclient \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o lab -g lab -m 0750 /srv/transfer
COPY config/smb.conf /etc/samba/smb.conf
COPY --chmod=755 config/start-file.sh /usr/local/bin/flatland-start-file
CMD ["flatland-start-file"]

FROM workload AS jump
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client sshpass \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["flatland-setup-routes"]
CMD ["sleep", "infinity"]

FROM debian:bookworm-slim AS router
RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 nftables ulogd2 \
    && rm -rf /var/lib/apt/lists/*
COPY config/ulogd.conf /etc/flatland/ulogd.conf
COPY --chmod=755 config/start-router.sh /usr/local/bin/flatland-start-router
ENTRYPOINT ["flatland-start-router"]
