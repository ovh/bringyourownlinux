#!/bin/sh
# This script prepares an Alpine Linux cloud image for OVHcloud baremetal servers

set -euo pipefail

# Update the system
apk update && apk upgrade

# Install useful packages for baremetal (RAID/LVM/filesystems/microcodes)
# We need to install packages that support hardware components commonly found in OVH baremetal servers
apk add --no-cache \
    mdadm \
    lvm2 \
    btrfs-progs \
    dosfstools \
    xfsprogs \
    linux-firmware-intel \
    intel-ucode \
    amd-ucode \
    openrc

# Remove Network configuration
rm -f /etc/network/interfaces

# Configure GRUB for proper boot on baremetal
# Alpine uses OpenRC instead of systemd, so we need to adjust accordingly
# Set default GRUB parameters
echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' > /etc/default/grub
echo 'GRUB_CMDLINE_LINUX="nomodeset"' >> /etc/default/grub
echo 'GRUB_GFXPAYLOAD_LINUX="text"' >> /etc/default/grub

# Add mdadm, LVM and net hooks to the initramfs
# In Alpine, we need to ensure the right modules are included
echo 'MODULES="mdraid lvm2"' > /etc/mkinitfs/modules
echo 'HOOKS="mount rootfs"' > /etc/mkinitfs/hooks

# Remove machine-id, it is regenerated during OS installation
rm -f /etc/machine-id

# Clean package cache
apk cache clean