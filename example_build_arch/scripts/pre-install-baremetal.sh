#!/bin/bash

set -euo pipefail

# This script prepares an Arch Linux cloud image for OVH baremetal servers

# Update the system and install necessary packages for baremetal deployment
pacman -Syu --noconfirm

# Install packages needed for baremetal deployment:
# - mdadm: software RAID support
# - lvm2: logical volume management
# - btrfs-progs: Btrfs filesystem support
# - dosfstools: FAT filesystem support (needed for EFI partitions)
# - grub: bootloader
# - efibootmgr: UEFI boot manager
# - intel-ucode, amd-ucode: CPU microcode updates
pacman -S --noconfirm --needed \
    mdadm \
    lvm2 \
    btrfs-progs \
    dosfstools \
    grub \
    efibootmgr \
    intel-ucode \
    amd-ucode \
    linux \
    linux-headers

# Install ZFS support (from AUR or archzfs repo if configured)
# Note: This is optional and may require archzfs repository to be configured
# Uncomment if ZFS support is needed:
# if ! pacman -Qi zfs-linux &>/dev/null; then
#     # ZFS installation would go here
#     # This typically requires the archzfs repository
#     echo "ZFS packages not installed. Configure archzfs repository if ZFS support is needed."
# fi

# Configure GRUB defaults for baremetal servers
# Remove quiet mode and add necessary kernel parameters
if [ -f /etc/default/grub ]; then
    # Backup original config
    cp /etc/default/grub /etc/default/grub.bak

    # Update GRUB configuration for baremetal
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="nomodeset iommu=pt"/' /etc/default/grub

    # Add text mode for better compatibility
    if ! grep -q "^GRUB_GFXPAYLOAD_LINUX" /etc/default/grub; then
        echo 'GRUB_GFXPAYLOAD_LINUX="text"' >> /etc/default/grub
    else
        sed -i 's/GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX="text"/' /etc/default/grub
    fi

    # Ensure GRUB timeout is reasonable
    sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
fi

# Configure mkinitcpio for baremetal (disable autodetect to include all drivers)
if [ -f /etc/mkinitcpio.conf ]; then
    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

    # IMPORTANT: Include mdadm_udev for RAID support (RAID 0, RAID 1, etc)
    # Remove autodetect hook - we need ALL drivers for baremetal
    sed -i 's/^HOOKS=.*/HOOKS=(base systemd modconf kms keyboard sd-vconsole block mdadm_udev filesystems fsck)/' /etc/mkinitcpio.conf

    # Add NVMe, SATA, and RAID modules explicitly
    sed -i 's/^MODULES=.*/MODULES=(nvme nvme_core ahci sd_mod md_mod raid0 raid1 raid10 raid456)/' /etc/mkinitcpio.conf

    # Regenerate initramfs with all modules including RAID
    mkinitcpio -P
fi

# Enable necessary services for baremetal
systemctl enable sshd
systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Configure mdadm if config exists
if [ -f /etc/mdadm.conf ]; then
    # Backup and regenerate mdadm configuration
    mv /etc/mdadm.conf /etc/mdadm.conf.bak || true
fi

# Remove machine-id so a new one will be generated on first boot
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clean package cache
pacman -Scc --noconfirm || true

echo "Arch Linux baremetal preparation completed successfully"
