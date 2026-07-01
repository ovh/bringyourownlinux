#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

### Step 1: Console configuration ###

configure_console() {
    local cmdline
    cmdline=$(cat /proc/cmdline)

    # Extract all console= parameters
    local console_params
    console_params=$(echo "$cmdline" | grep -oP 'console=\S+' || true)

    if [ -z "$console_params" ]; then
        return
    fi

    # Read current GRUB_CMDLINE_LINUX value (without quotes)
    local current
    current=$(sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"/\1/p' /etc/default/grub)

    # Append each console= param if not already present
    for param in $console_params; do
        if ! echo " $current " | grep -qF " $param "; then
            current="$current $param"
        fi
    done
    current=$(echo "$current" | sed 's/^ *//')

    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$current\"|" /etc/default/grub

    # Check for serial console (ttyS*)
    local serial_param
    serial_param=$(echo "$console_params" | grep 'ttyS' | tail -1 || true)

    # No serial console: nothing more to configure.
    if [[ -z "$serial_param" ]]; then
        return
    fi

    # Parse console=ttyS<unit>,<speed><parity><word> (e.g. ttyS0,115200n8)
    local tty_part settings_part unit speed parity_char parity word
    tty_part=$(echo "$serial_param" | sed 's/console=//' | cut -d, -f1)
    settings_part=$(echo "$serial_param" | sed 's/console=//' | cut -d, -f2)

    unit=$(echo "$tty_part" | sed 's/ttyS//')
    speed=$(echo "$settings_part" | grep -oP '^\d+')
    parity_char=$(echo "$settings_part" | grep -oP '\d+\K[noe]')
    word=$(echo "$settings_part" | grep -oP '[noe]\K\d')

    case "$parity_char" in
        n) parity="no" ;;
        o) parity="odd" ;;
        e) parity="even" ;;
    esac

    # Set GRUB_TERMINAL (replace if exists, append if not)
    if grep -q '^GRUB_TERMINAL=' /etc/default/grub; then
        sed -i 's|^GRUB_TERMINAL=.*|GRUB_TERMINAL="console serial"|' /etc/default/grub
    else
        echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub
    fi

    # Set GRUB_SERIAL_COMMAND (replace if exists, append if not)
    local serial_cmd="serial --unit=$unit --speed=$speed --parity=$parity --word=$word"
    if grep -q '^GRUB_SERIAL_COMMAND=' /etc/default/grub; then
        sed -i "s|^GRUB_SERIAL_COMMAND=.*|GRUB_SERIAL_COMMAND=\"$serial_cmd\"|" /etc/default/grub
    else
        echo "GRUB_SERIAL_COMMAND=\"$serial_cmd\"" >> /etc/default/grub
    fi
}

### Step 2: ZFS setup ###

install_zfs() {
    if ! lsblk -lno FSTYPE | grep -qi zfs_member; then
        echo "    No ZFS partitions detected, skipping."
        return
    fi
    echo "    ZFS partitions detected, installing packages (DKMS build)..."

    # Debian has no precompiled zfs.ko — DKMS at install time is the only
    # option (unlike Ubuntu, where the module ships with the kernel and the
    # userland is preinstalled in the image).
    apt-get install --no-install-recommends -y linux-headers-amd64 zfs-dkms zfs-initramfs zfs-zed
    systemctl enable zfs-import-scan.service
    # No explicit zgenhostid: the zfsutils-linux postinst (which just ran, since
    # zfs is installed here on the target) generates /etc/hostid via zgenhostid
    # when it is missing. A per-target hostid is therefore already in place.
    # (The Ubuntu MIB must force one because zfs is preinstalled in the image,
    # so the postinst baked a single shared /etc/hostid at build time.)

    # Create ZFS list cache so zfs-mount-generator generates one systemd
    # mount unit per dataset. Without this, /boot/efi can be masked by a
    # ZFS /boot mount. See PUBM-45416.
    mkdir -p /etc/zfs/zfs-list.cache

    local pool altroot
    for pool in $(zpool list -Ho name); do
        altroot=$(zpool get -Ho value altroot "$pool")

        # Properties taken from zed history_event-zfs-list-cacher.sh
        # https://github.com/openzfs/zfs/blob/zfs-2.3.2/cmd/zed/zed.d/history_event-zfs-list-cacher.sh.in#L69-L76
        local PROPS="name,mountpoint,canmount,atime,relatime,devices,exec\
,readonly,setuid,nbmand,encroot,keylocation\
,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for\
,org.openzfs.systemd:before,org.openzfs.systemd:after\
,org.openzfs.systemd:wanted-by,org.openzfs.systemd:required-by\
,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore"

        zfs list -Ho "$PROPS" -r "$pool" > "/etc/zfs/zfs-list.cache/$pool"

        if [ "$altroot" != "-" ]; then
            # zfs list -H outputs tab-separated fields; tabs must be preserved
            # or zfs-mount-generator fails with "not enough tokens"
            awk -v ar="$altroot" 'BEGIN{FS=OFS="\t"} {
                sub("^"ar, "", $2)
                sub("^$", "/", $2)
                print
            }' "/etc/zfs/zfs-list.cache/$pool" > "/etc/zfs/zfs-list.cache/$pool.tmp"
            mv "/etc/zfs/zfs-list.cache/$pool.tmp" "/etc/zfs/zfs-list.cache/$pool"
        fi
    done
}

### Step 3: mdadm configuration ###

configure_mdadm() {
    # /etc/mdadm.conf is generated during partitioning, but
    # /etc/mdadm/mdadm.conf takes precedence and is the canonical location.
    # Remove the stale one so it's never accidentally read.
    rm -f /etc/mdadm.conf
    # mkconf is Debian's mdadm helper that scans running arrays and writes
    # a valid /etc/mdadm/mdadm.conf — force-generate rm's and rewrites the file
    # itself (internal `exec >$CONFIG`), so no output redirect is needed.
    /usr/share/mdadm/mkconf force-generate
}

### Step 4: GRUB installation ###

# Map a block device to its first /dev/disk/by-id/ link.
# Sort with LC_COLLATE=C.UTF-8 for locale-independent ordering, matching how
# grub's postinst stores install_devices — another link would keep the device
# from matching on later dpkg-reconfigure. See PUBM-23086.
by_id_of() {
    local dev_real
    dev_real=$(readlink -f "$1")
    LC_COLLATE=C.UTF-8 ls -1 /dev/disk/by-id/ 2>/dev/null | sort | while read -r link; do
        if [ "$(readlink -f "/dev/disk/by-id/$link")" = "$dev_real" ]; then
            echo "/dev/disk/by-id/$link"
            break
        fi
    done
}

# Join arguments with ", " for debconf multiselect values — manually, because
# the separator is two characters and IFS-based joins use only its first one.
join_debconf() {
    local result
    result=$(printf '%s, ' "$@")
    echo "${result%', '}"
}

# Find boot disk(s) for GRUB legacy installation:
# 1. Find device(s) backing /boot (or / if /boot is not a separate mount)
# 2. If /boot is on ZFS, resolve to the pool's underlying devices
# 3. If /boot is on mdadm RAID, resolve to the RAID's member block devices
# 4. Walk each device up to its parent disk
# 5. Map each disk to its first /dev/disk/by-id/ link
get_boot_disks() {
    local boot_source
    boot_source=$(findmnt -n -o SOURCE /boot 2>/dev/null || findmnt -n -o SOURCE /)

    local devices=()

    # Check if boot source is a ZFS dataset
    local maybe_pool
    maybe_pool=$(echo "$boot_source" | cut -d/ -f1)
    if zpool list "$maybe_pool" &>/dev/null; then
        # ZFS: resolve the pool to its real /dev partition paths.
        # -L resolves symlinked vdev names, -P prints full paths; without
        # them, leaf vdevs print as bare names (sda3, wwn-...) and the /dev/
        # filter below would match nothing, yielding no install devices.
        while IFS= read -r dev; do
            devices+=("$dev")
        done < <(zpool status -LP "$maybe_pool" | awk '/ONLINE/ {print $1}' | grep '^/dev/')
    else
        devices+=("$boot_source")
    fi

    # Walk each device up its dependency chain — lsblk -s lists the device
    # itself, then what it sits on (md members, then their disks) — and keep
    # the whole disks, deduplicated. grub-install cannot write to an md
    # device (diskfilter writes are not supported), so md sources resolve to
    # their member disks here.
    local disk by_id_link disks=()
    while IFS= read -r disk; do
        by_id_link=$(by_id_of "$disk")
        disks+=("${by_id_link:-$disk}")
    done < <(lsblk -snpl -o TYPE,NAME "${devices[@]}" | awk '$1 == "disk" && !seen[$2]++ {print $2}')

    join_debconf "${disks[@]}"
}

install_grub() {
    if [ -d /sys/firmware/efi ]; then
        echo "    UEFI boot detected."

        # No grub-efi/install_devices preseed here: that debconf key and the
        # multi-ESP handling behind it (grub-multi-install) are Ubuntu
        # patches to grub; Debian's grub-efi postinst has no such machinery.
        # The explicit grub-install below installs to the mounted ESP.
        apt-get install --no-install-recommends -y grub-efi-amd64
        # --bootloader-id fixes the ESP path to \EFI\debian\grubx64.efi.
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --no-nvram
        apt-get purge -y grub-pc-bin
    else
        echo "    Legacy BIOS boot detected."
        local boot_disks
        boot_disks=$(get_boot_disks)
        echo "grub-pc grub-pc/install_devices multiselect $boot_disks" | debconf-set-selections
        # The fresh install's postinst runs grub-install on the preseeded
        # install_devices, writing the MBR boot code on each disk.
        apt-get install --no-install-recommends -y grub-pc
        apt-get purge -y grub-efi-amd64-bin
    fi

    # Post-GRUB cleanup: autoremove but keep cache for customers
    apt-get autoremove -y
}

### Step 5: System finalization ###

finalize() {
    systemd-machine-id-setup
    # grub.cfg is generated by the grub package postinst in install_grub; no
    # explicit update-grub needed here.
    update-initramfs -u
    rm -rf /root/.ovh
}

### Main ###

exec > >(tee -a /var/log/ovh-make-bootable.log) 2>&1

echo ">>> Configuring console..."
configure_console

echo ">>> Setting up ZFS..."
install_zfs

echo ">>> Configuring mdadm..."
configure_mdadm

echo ">>> Installing GRUB..."
install_grub

echo ">>> Finalizing system..."
finalize

echo ">>> make_image_bootable.sh complete."
