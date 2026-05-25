#!/bin/bash
# This script prepares an Arch Linux cloud image for OVHcloud baremetal servers

set -euo pipefail

# Update the system
pacman -Syu --noconfirm

# Install useful packages for baremetal (RAID/LVM/filesystems/microcodes)
# linux-firmware-intel is required because it contains ice.pkg for Intel E810
# NICs
# mkinitcpio-nfs-utils is required to load networking drivers in the initramfs,
# having NICs initialized early is necessary for cloud-init to work properly
pacman -S --noconfirm --needed \
    mdadm \
    lvm2 \
    btrfs-progs \
    dosfstools \
    xfsprogs \
    linux-firmware-intel \
    intel-ucode \
    amd-ucode \
    mkinitcpio-nfs-utils

# Remove Network configuration
rm -f /etc/systemd/network/*.network

# Use the same options for the normal and recovery modes
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
# Disable kernel modesetting (causes display issues with some KVM models)
sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="nomodeset"/' /etc/default/grub
# Boot in text mode for better compatibility
sed -i 's/GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX="text"/' /etc/default/grub

# Add mdadm, LVM and net hooks
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block mdadm_udev lvm2 net filesystems fsck)/' /etc/mkinitcpio.conf

# Remove machine-id, it is regenerated during OS installation
rm -f /etc/machine-id

# Clean package cache
pacman -Scc --noconfirm
