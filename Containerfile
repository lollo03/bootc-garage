FROM quay.io/fedora/fedora-bootc:43

ARG GARAGE_VERSION=2.1.0
ARG HOSTNAME=bohkup
ARG SSH_AUTHORIZED_KEYS

# --- System & ZFS Setup ---
RUN echo "$HOSTNAME" > /etc/hostname && \
    echo "127.0.0.1 $HOSTNAME" >> /etc/hosts && \
    echo "::1       $HOSTNAME" >> /etc/hosts

RUN set -eu; mkdir -p /usr/ssh && \
    echo 'AuthorizedKeysFile /usr/ssh/%u.keys .ssh/authorized_keys .ssh/authorized_keys2' >> /etc/ssh/sshd_config.d/30-auth-system.conf
RUN [ -z "$SSH_AUTHORIZED_KEYS" ] || echo "$SSH_AUTHORIZED_KEYS" > /usr/ssh/root.keys

#ZFS Kernel Module Build
RUN dnf install -y https://zfsonlinux.org/fedora/zfs-release.fc$(rpm -E %fedora).noarch.rpm && \
    dnf install -y \
        "kernel-devel-$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}')" \
        zfs \
        dkms \
        gcc \
        make && \
    dkms autoinstall --verbose --kernelver $(rpm -q kernel --qf "%{VERSION}-%{RELEASE}.%{ARCH}") && \
    systemctl enable zfs-import-cache zfs-import-scan zfs-mount zfs-share zfs-zed zfs.target && \
    dnf remove -y kernel-devel gcc make && \
    dnf clean all

# --- Application Setup ---

RUN curl "https://pkgs.tailscale.com/stable/fedora/tailscale.repo" -o "/etc/yum.repos.d/tailscale.repo" && \
    dnf install -y \
    qemu-guest-agent \
    tailscale \
    wireguard-tools \
    nfs-utils \
    fish htop jq plocate rsync screen tcpdump tmux tree vim yq wget \
    cowsay figlet lolcat && \
    dnf clean all

RUN systemctl enable qemu-guest-agent tailscaled

# Install Garage (S3)
RUN wget "https://garagehq.deuxfleurs.fr/_releases/v$GARAGE_VERSION/x86_64-unknown-linux-musl/garage" && \
    chmod +x garage && \
    mv garage /usr/local/bin/garage

RUN mkdir -p /var/lib/garage/meta /var/lib/garage/data
RUN cat <<EOF > /etc/garage.toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
metadata_auto_snapshot_interval = "24h"
metadata_auto_snapshot_retention = 7
db_engine = "sqlite"
replication_factor = 1
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "__RPC_SECRET__"
[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.$HOSTNAME.lolloandr.com"
[admin]
api_bind_addr = "[::]:3903"
admin_token = "__ADMIN_TOKEN__"
metrics_token = "__METRICS_TOKEN__"
EOF

COPY ./config/garage.service /usr/local/lib/systemd/system/garage.service
RUN echo "EDITOR=vim" >> /etc/environment
RUN usermod -s /usr/bin/fish root

# Firstboot Scripts
COPY ./config/firstboot.service /usr/local/lib/systemd/system/firstboot.service
COPY ./config/firstboot.sh /usr/local/bin/firstboot.sh
RUN chmod +x /usr/local/bin/firstboot.sh && \
    mkdir -p /etc/firstboot.d && \
    systemctl enable firstboot

RUN bootc container lint