#!/bin/bash

set -euo pipefail

podman build \
  -t localhost/bootc-zfs:latest \
  --build-arg SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDcQTgKMEsnpqM1taZp4XlnaR2q08lK9GOX9J1FeZU5 lollo@nixlol' \
  .

podman image save localhost/bootc-zfs:latest | sudo podman image load

sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(pwd)/output:/output \
    -v $(pwd)/config.toml:/config.toml \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --config /config.toml --rootfs=xfs \
    localhost/bootc-zfs:latest

echo "Starting vm..."

sudo qemu-system-x86_64 \
    -m 4G \
    -smp 2 \
    -enable-kvm \
    -cpu host \
    -drive file=./output/qcow2/disk.qcow2,format=qcow2 \
    -net nic,model=virtio \
    -net user,hostfwd=tcp::2222-:22