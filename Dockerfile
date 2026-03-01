# syntax=docker/dockerfile:1

FROM debian:trixie-slim

ARG TARGETARCH
ARG VERSION="0.0.4-beta"
ARG VERSION_UTK="1.2.0"
ARG VERSION_VNC="1.7.0-beta"
ARG VERSION_PASST="2025_09_19"
ARG BUILD_DATE
ARG REVISION
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"


LABEL org.opencontainers.image.authors="Maya <mayas.alas@email.gnx>"
LABEL org.opencontainers.image.title="Tailnet"
LABEL org.opencontainers.image.description="Tailnet is a containerized environment."
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.url="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.documentation="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.vendor="GNX Labs"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${REVISION}"
LABEL org.opencontainers.image.base.name="tailnet:${VERSION}"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        bc \
        jq \
        xxd \
        tini \
        wget \
        7zip \
        curl \
        ovmf \
        fdisk \
        nginx \
        swtpm \
        procps \
        ethtool \
        iptables \
        iproute2 \
        dnsmasq \
        xz-utils \
        apt-utils \
        net-tools \
        e2fsprogs \
        qemu-utils \
        websocketd \
        iputils-ping \
        genisoimage \
        inotify-tools \
        netcat-openbsd \
        ca-certificates \
        qemu-system-x86 && \
    wget "https://github.com/qemus/passt/releases/download/v${VERSION_PASST}/passt_${VERSION_PASST}_${TARGETARCH}.deb" -O /tmp/passt.deb -q && \
    dpkg -i /tmp/passt.deb && \
    apt-get clean && \
    mkdir -p /etc/qemu && \
    echo "allow br0" > /etc/qemu/bridge.conf && \
    mkdir -p /usr/share/novnc && \
    wget "https://github.com/novnc/noVNC/archive/refs/tags/v${VERSION_VNC}.tar.gz" -O /tmp/novnc.tar.gz -q --timeout=10 && \
    tar -xf /tmp/novnc.tar.gz -C /tmp/ && \
    cd "/tmp/noVNC-${VERSION_VNC}" && \
    mv app core vendor package.json ./*.html /usr/share/novnc && \
    unlink /etc/nginx/sites-enabled/default && \
    sed -i 's/^worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf && \
    echo "$VERSION_ARG" > /run/version && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./web /var/www/
COPY --chmod=664 ./web/conf/defaults.json /usr/share/novnc
COPY --chmod=664 ./web/conf/mandatory.json /usr/share/novnc
COPY --chmod=744 ./web/conf/nginx.conf /etc/nginx/default.conf

ADD --chmod=755 "https://github.com/qemus/fiano/releases/download/v${VERSION_UTK}/utk_${VERSION_UTK}_${TARGETARCH}.bin" /run/utk.bin

VOLUME /storage
EXPOSE 22 5900 8006

ENV CPU_CORES="max"
ENV RAM_SIZE="max"
ENV DISK_SIZE="max"
ENV SUPPORT="https://github.com/mayas-alas/tailnet"
ENV ENGINE="podman"
ENV BOOT="proxmox"
ENV VMX="Y"
ENV MACHINE="q35"
ENV KVM="Y"
ENV GPU="N"
ENV DISK_FMT="qcow2"
ENV DISK_TYPE="scsi"
ENV DISK_IO="io_uring"
ENV DISK_CACHE="writeback"
ENV NETWORK="passt"
ENV MTU="1280"
ENV DEBUG="Y"
ENV USER_PORTS="8006"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
