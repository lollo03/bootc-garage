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


# hadolint ignore=DL3041
RUN dnf install -y "https://zfsonlinux.org/fedora/zfs-release-3-0.fc$(rpm -E %fedora).noarch.rpm" && \
    #  Get the Image's Kernel Version (Not the Host's!)
    KERNEL_VERSION="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    dnf install -y \
        "kernel-devel-${KERNEL_VERSION}" \
        zfs \
        dkms \
        gcc \
        make && \
    # Compile the Module (Explicitly)
    dkms autoinstall --verbose --kernelver "${KERNEL_VERSION}" && \
    echo zfs > /etc/modules-load.d/zfs.conf && \
    systemctl enable zfs-import-cache zfs-import-scan zfs-mount zfs-share zfs-zed zfs.target && \
    dnf remove -y kernel-devel gcc make && \
    dnf clean all

# --- Application Setup ---

# hadolint ignore=DL3041
RUN curl -L "https://pkgs.tailscale.com/stable/fedora/tailscale.repo" -o "/etc/yum.repos.d/tailscale.repo" && \
    dnf install -y \
    qemu-guest-agent \
    tailscale \
    wireguard-tools \
    nfs-utils \
    fish htop jq plocate rsync screen tcpdump tmux tree vim yq \
    cowsay figlet lolcat && \
    dnf clean all

RUN systemctl enable qemu-guest-agent tailscaled

# Install Garage (S3)
RUN curl -L "https://garagehq.deuxfleurs.fr/_releases/v$GARAGE_VERSION/x86_64-unknown-linux-musl/garage" -o garage && \
    chmod +x garage && \
    mv garage /usr/local/bin/garage

RUN mkdir -p /var/lib/garage/meta /var/lib/garage/data

# hadolint ignore=DL3059
RUN printf 'metadata_dir = "/var/lib/garage/meta"\n\
data_dir = "/var/lib/garage/data"\n\
metadata_auto_snapshot_interval = "24h"\n\
metadata_auto_snapshot_retention = 7\n\
db_engine = "sqlite"\n\
replication_factor = 1\n\
rpc_bind_addr = "[::]:3901"\n\
rpc_public_addr = "127.0.0.1:3901"\n\
[s3_api]\n\
s3_region = "garage"\n\
api_bind_addr = "[::]:3900"\n\
root_domain = ".s3.%s.lolloandr.com"\n\
[admin]\n\
api_bind_addr = "[::]:3903"\n' "$HOSTNAME" > /etc/garage.toml

COPY ./config/garage.service /usr/local/lib/systemd/system/garage.service
RUN echo "EDITOR=vim" >> /etc/environment
# hadolint ignore=DL3059
RUN usermod -s /usr/bin/fish root

# Firstboot Scripts
COPY ./config/firstboot.service /usr/local/lib/systemd/system/firstboot.service
COPY ./config/firstboot.sh /usr/local/bin/firstboot.sh
RUN chmod +x /usr/local/bin/firstboot.sh && \
    mkdir -p /etc/firstboot.d && \
    systemctl enable firstboot

RUN bootc container lint