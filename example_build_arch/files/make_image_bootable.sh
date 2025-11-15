#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
# file except in compliance with the License. You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

###########################################################
# This script makes an Arch Linux image bootable on OVH  #
# baremetal servers after deployment                      #
###########################################################

# Only exit on critical failures, allow some commands to fail
set -e

# Get console parameters from rescue's cmdline
console_parameters="$(grep -Po '\bconsole=\S+' /proc/cmdline | paste -s -d" " || true)"
if [ -n "$console_parameters" ] && [ -f /etc/default/grub ]; then
    if ! grep -q "$console_parameters" /etc/default/grub 2>/dev/null; then
        sed -Ei "s/(^GRUB_CMDLINE_LINUX=.*)\"\$/\1 $console_parameters\"/" /etc/default/grub || true
    fi
fi

# Handle mdadm configuration if RAID is present
if [ -e /proc/mdstat ] && grep -q md /proc/mdstat 2>/dev/null; then
    mdadm --detail --scan > /etc/mdadm.conf 2>/dev/null || true
fi

# Configure mkinitcpio hooks for RAID if needed
if [ -e /proc/mdstat ] && grep -q md /proc/mdstat 2>/dev/null; then
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q mdadm_udev /etc/mkinitcpio.conf; then
            sed -i 's/^HOOKS=(\(.*\)block/HOOKS=(\1block mdadm_udev/' /etc/mkinitcpio.conf || true
        fi
    fi
fi

# Detect boot mode and install GRUB
if [ -d /sys/firmware/efi ]; then
    # UEFI mode
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --no-nvram
else
    # BIOS mode
    # Find the root device
    root_device=$(findmnt -n -o SOURCE / | head -1)

    if [[ "$root_device" =~ /dev/md ]]; then
        # RAID: install to all member disks
        for disk in $(lsblk -ndo PKNAME "$root_device" | sort -u); do
            grub-install --target=i386-pc "/dev/$disk" || true
        done
    else
        # Single disk: find parent disk
        disk_device=$(lsblk -npo PKNAME "$root_device" | head -1)
        if [ -n "$disk_device" ]; then
            grub-install --target=i386-pc "$disk_device"
        fi
    fi
fi

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Regenerate initramfs
mkinitcpio -P

# Generate unique machine-id
systemd-machine-id-setup

# Cleanup
rm -fr /root/.ovh/

exit 0
