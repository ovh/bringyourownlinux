#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
# file except in compliance with the License. You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

# This script makes an Arch Linux image bootable on OVHcloud baremetal servers

set -eo pipefail

configure_console() {
    echo "Getting console parameters from the cmdline"
    # Get the right console parameters (including SOL if available) from the
    # rescue's cmdline - PUBM-16534
    console_parameters="$(grep -Po '\bconsole=\S+' /proc/cmdline | paste -s -d" ")"
    if ! grep '^GRUB_CMDLINE_LINUX="' /etc/default/grub | grep -qF "$console_parameters"; then
        sed -Ei "s/(^GRUB_CMDLINE_LINUX=.*)\"\$/\1 $console_parameters\"/" /etc/default/grub
    fi

    # Also pass these parameters to GRUB
    parameters=$(sed -nE "s/.*\bconsole=ttyS([0-9]),([0-9]+)([noe])([0-9]+)\b.*/\1 \2 \3 \4/p" /proc/cmdline)
    if [[ ! "$parameters" ]]; then
        # No SOL, nothing to do
        return
    fi
    read -r unit speed parity bits <<< "$parameters"
    declare -A parities=([o]=odd [e]=even [n]=no)
    parity="${parities["$parity"]}"
    serial_command="serial --unit=$unit --speed=$speed --parity=$parity --word=$bits"

    if grep -qFx 'GRUB_TERMINAL="console serial"' /etc/default/grub; then
        # Configuration already applied
        return
    fi

    sed -i \
        -e "/^# Uncomment to disable graphical terminal/d" \
        -e "s/^#GRUB_TERMINAL=.*/GRUB_TERMINAL=\"console serial\"\nGRUB_SERIAL_COMMAND=\"$serial_command\"/" \
        /etc/default/grub
}

# Detect boot mode and install GRUB
if [ -d /sys/firmware/efi ]; then
    echo "INFO - GRUB will be configured for UEFI boot"
    # Pass --no-nvram to avoid changing the boot order, the server needs to boot via PXE
    grub-install --target=x86_64-efi --no-nvram
else
    echo "INFO - GRUB will be configured for legacy boot"
    bootDevice="$(findmnt -A -c -e -l -n -T /boot/ -o SOURCE)"
    realBootDevices="$(lsblk -n -p -b -l -o TYPE,NAME $bootDevice -s | awk '$1 == "disk" && !seen[$2]++ {print $2}')"
    # realBootDevices are disks at this point
    for realBootDevice in $realBootDevices; do
        echo "INFO - GRUB will be configured on disk ${realBootDevice}"
        # realBootDevice is the boot disk device canonical path
        grub-install --target=i386-pc --force "$realBootDevice"
    done
fi

# Configure SOL console
configure_console

# Generate unique machine-id
systemd-machine-id-setup

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Regenerate initramfs to include e.g. mdadm.conf and required kernel modules
mkinitcpio -P

# Cleanup
rm -fr /root/.ovh/
