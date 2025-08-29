#!/bin/bash

set -eo pipefail

export DEBIAN_FRONTEND=noninteractive
# For the sort calls to behave consistently with paths like these - PUBM-23086:
# /dev/disk/by-id/nvme-eui.e8238fa6bf530001001b44455555555-part1
# /dev/disk/by-id/nvme-WDC_CL_SN720_SDAQNTW-512G-2000_xxxx-part1
export LC_COLLATE=C.UTF-8

# This script will run inside the newly installed system, no need to call chroot

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

# The image contains /etc/mdadm/mdadm.conf which was created by mdadm's postinst script.
# It takes precedence over /etc/mdadm.conf which is generated during partitioning_apply.
# This means /etc/mdadm.conf will never be read so we can delete it.
rm -f /etc/mdadm.conf
# In order to create a prettier config file, we regenerate /etc/mdadm/mdadm.conf
# with a command similar to that of mdadm's postinst script.
/usr/share/mdadm/mkconf force-generate
# To update mdadm.conf inside the initramfs (it will be the same as /etc/mdadm/mdadm.conf)
update-initramfs -u

configure_console

realBootDevicesById=()
if [ -d /sys/firmware/efi ]; then
    echo "INFO - GRUB will be configured for UEFI boot"
    # Find all EFI system partitions
    for realBootDevice in $(lsblk -pnlo NAME,LABEL,TYPE | awk '$3 == "part" && $2 == "EFI_SYSPART" { print $1 }'); do
        # See the legacy boot section below for details about the sort and head logic.
        # https://git.launchpad.net/~ubuntu-core-dev/grub/+git/ubuntu/tree/debian/grub-multi-install?h=debian/2.06-2ubuntu7#n220
        realBootDevicesById+=($(find -L /dev/disk/by-id/ -type b -samefile "$realBootDevice" | sort -us | head -n1))
    done
    echo "grub-efi-amd64 grub-efi/install_devices multiselect $(sed 's/ /, /g' <<< "${realBootDevicesById[@]}")" | debconf-set-selections
    apt-get -y install grub-efi-amd64
    apt-get -y purge grub-pc-bin
else
    echo "INFO - GRUB will be configured for legacy boot"
    bootDevice="$(findmnt -A -c -e -l -n -T /boot/ -o SOURCE)"
    realBootDevices="$(lsblk -n -p -b -l -o TYPE,NAME $bootDevice -s | awk '$1 == "disk" && !seen[$2]++ {print $2}')"
    # realBootDevices are disks at this point
    for realBootDevice in $realBootDevices; do
        # When GRUB is manually installed, grub-pc/install_devices contains values from /dev/disk/by-id.
        # Each device has two links in that folder, e.g. ata-HGST_HUS726040ALA610_KXXXX and wwn-0x5000cca25defa844.
        # The postinst script for grub-pc keeps the first link after sorting them, see
        # https://salsa.debian.org/grub-team/grub/-/blob/debian/2.04-20/debian/postinst.in#L89
        # Using another link would cause it not to show up in the prompt to reconfigure the package.
        realBootDevicesById+=($(find -L /dev/disk/by-id/ -type b -samefile "$realBootDevice" | sort -us | head -n1))
    done
    echo "grub-pc grub-pc/install_devices multiselect $(sed 's/ /, /g' <<< "${realBootDevicesById[@]}")" | debconf-set-selections
    apt-get -y install grub-pc
    apt-get -y purge grub-efi-amd64-bin
fi
apt-get -y autoremove

# Generate a new unique machine-id for this server
systemd-machine-id-setup

# suicide cleanup
rm -fr /root/.ovh/
