#!/bin/bash
set -euo pipefail

# This script makes an Alpine Linux image bootable on OVHcloud baremetal servers.
# It runs chrooted inside the freshly deployed filesystem, right before the first
# reboot. bash, GNU grep/sed, grub and util-linux are installed by provision.sh.

### Step 1: Console configuration ###

configure_console() {
    local cmdline console_params
    cmdline=$(cat /proc/cmdline)
    console_params=$(echo "$cmdline" | grep -oP 'console=\S+' || true)
    [ -z "$console_params" ] && return

    local current param
    current=$(sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"/\1/p' /etc/default/grub)
    for param in $console_params; do
        echo " $current " | grep -qF " $param " || current="$current $param"
    done
    current=$(echo "$current" | sed 's/^ *//')
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$current\"|" /etc/default/grub

    local serial_param
    serial_param=$(echo "$console_params" | grep 'ttyS' | tail -1 || true)
    [ -z "$serial_param" ] && return

    local tty_part settings_part unit speed parity_char parity word
    tty_part=$(echo "$serial_param" | sed 's/console=//' | cut -d, -f1)
    settings_part=$(echo "$serial_param" | sed 's/console=//' | cut -d, -f2)
    unit=$(echo "$tty_part" | sed 's/ttyS//')
    speed=$(echo "$settings_part" | grep -oP '^\d+')
    parity_char=$(echo "$settings_part" | grep -oP '\d+\K[noe]')
    word=$(echo "$settings_part" | grep -oP '[noe]\K\d')
    case "$parity_char" in
        n) parity="no" ;; o) parity="odd" ;; e) parity="even" ;;
    esac

    if grep -q '^GRUB_TERMINAL=' /etc/default/grub; then
        sed -i 's|^GRUB_TERMINAL=.*|GRUB_TERMINAL="console serial"|' /etc/default/grub
    else
        echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub
    fi
    local serial_cmd="serial --unit=$unit --speed=$speed --parity=$parity --word=$word"
    if grep -q '^GRUB_SERIAL_COMMAND=' /etc/default/grub; then
        sed -i "s|^GRUB_SERIAL_COMMAND=.*|GRUB_SERIAL_COMMAND=\"$serial_cmd\"|" /etc/default/grub
    else
        echo "GRUB_SERIAL_COMMAND=\"$serial_cmd\"" >> /etc/default/grub
    fi
}

### Step 2: mdadm configuration ###

configure_mdadm() {
    # Record running arrays so the initramfs (mdadm_udev) assembles them.
    mdadm --detail --scan > /etc/mdadm.conf 2>/dev/null || true
}

### Step 3: GRUB installation ###

install_grub() {
    if [ -d /sys/firmware/efi ]; then
        echo "    UEFI boot detected."
        # --efi-directory: OVHcloud partitioning mounts the ESP at /boot/efi.
        # --no-nvram: OVHcloud servers boot over the network; do not touch the
        # firmware boot order.
        # --bootloader-id fixes the ESP path to \EFI\alpine\grubx64.efi.
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=alpine --no-nvram
    else
        echo "    Legacy BIOS boot detected."
        local boot_device disks disk
        boot_device="$(findmnt -A -c -e -l -n -T /boot/ -o SOURCE)"
        disks="$(lsblk -n -p -b -l -o TYPE,NAME "$boot_device" -s \
            | awk '$1 == "disk" && !seen[$2]++ {print $2}')"
        for disk in $disks; do
            echo "    Installing GRUB on $disk"
            grub-install --target=i386-pc --force "$disk"
        done
    fi
}

### Step 4: System finalization ###

finalize() {
    # Alpine has no systemd-machine-id-setup: generate a fresh machine-id.
    tr -d '-' < /proc/sys/kernel/random/uuid > /etc/machine-id

    grub-mkconfig -o /boot/grub/grub.cfg

    # Regenerate the initramfs for the installed kernel (uname -r is the rescue
    # kernel here, so take the version from /lib/modules).
    local kernel_version
    kernel_version="$(ls -1 /lib/modules | head -n1)"
    mkinitfs "$kernel_version"

    rm -rf /root/.ovh
}

### Main ###

exec > >(tee -a /var/log/ovh-make-bootable.log) 2>&1

echo ">>> Configuring console..."
configure_console
echo ">>> Configuring mdadm..."
configure_mdadm
echo ">>> Installing GRUB..."
install_grub
echo ">>> Finalizing system..."
finalize
echo ">>> make_image_bootable.sh complete."
