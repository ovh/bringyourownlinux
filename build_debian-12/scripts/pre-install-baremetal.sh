#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Place the post-install script that the deployer runs, chrooted, on the target.
mkdir -p /root/.ovh
mv /tmp/make_image_bootable.sh /root/.ovh/make_image_bootable.sh
chmod +x /root/.ovh/make_image_bootable.sh

# Remove a cloud-init module from cloud.cfg, failing loudly if it is missing so
# an upstream rename is caught at build time rather than silently ignored.
disable_cloud_init_module() {
    local module="$1"
    grep -qE "^ *- $module\$" /etc/cloud/cloud.cfg \
        || { echo "ERROR: cloud-init module '$module' not found in cloud.cfg" >&2; exit 1; }
    sed -i -E "/^ *- $module\$/d" /etc/cloud/cloud.cfg
}

### Phase 1: GRUB preparation ###

# 10_cloud.cfg forces root=PARTUUID=, which is empty on bare-metal and yields an
# unbootable OS (PUBM-37334).
rm -f /etc/default/grub.d/10_cloud.cfg
# grub-cloud-amd64 misbehaves on bare-metal (PUBM-22667). Remove grub-efi-amd64-signed
# too: on legacy servers, purging grub-efi-amd64-bin while the signed package
# remains pulls in efibootmgr + systemd-boot as replacements. Purge the stock
# kernels so only the backported kernel installed below remains.
apt-get purge --allow-remove-essential -y grub-cloud-amd64 grub-efi-amd64-signed 'linux-image-*'

cp /usr/share/grub/default/grub /etc/default/grub
# nomodeset: KVM display on some boards (PUBM-22537).
# iommu=pt: avoids AMD kernel panics under load (PUBM-15188).
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="nomodeset iommu=pt"/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub

echo 'grub-efi-amd64 grub2/update_nvram boolean false' | debconf-set-selections

### Phase 2: Repository configuration ###

# Enable contrib + non-free (ZFS) and non-free-firmware (microcodes), and add
# bookworm-backports for the latest kernel. Handle both the deb822 (.sources)
# and the legacy one-line sources.list layout, whichever the base image ships.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i 's/^Components:.*/Components: main contrib non-free non-free-firmware/' \
        /etc/apt/sources.list.d/debian.sources
    cat > /etc/apt/sources.list.d/backports.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
else
    sed -i "s/\bmain\b/& contrib non-free non-free-firmware/" /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware" \
        > /etc/apt/sources.list.d/backports.list
fi
apt-get update

### Phase 3: Package installation ###

# Latest kernel from backports (replaces the stock kernels purged in Phase 1).
apt-get install --no-install-recommends -y -t bookworm-backports linux-image-amd64
# Bare-metal tooling: RAID/LVM/filesystems, microcodes, firmware, plus the
# partition tools used by the single-partition step below.
apt-get install --no-install-recommends -y \
    mdadm lvm2 btrfs-progs xfsprogs dosfstools rsync parted \
    amd64-microcode intel-microcode firmware-linux
apt-get dist-upgrade -y

### Phase 4: Cleanup (before the download-only steps so those persist) ###

apt-get autoremove --purge -y
apt-get clean

### Phase 4.5: Single-partition image (BYOL requires exactly one partition) ###
# The generic cloud image ships an ESP and a bios_grub stub alongside the Linux
# root. Merge the ESP into the root filesystem and delete the extra partitions;
# the target's real ESP is recreated by OVHcloud partitioning and
# make_image_bootable.sh reinstalls GRUB there at deploy time. blkdiscard before
# parted rm so the freed blocks are actually released in the qcow2.
root_disk="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")"
efi_dev="$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)"
if [ -n "$efi_dev" ]; then
    echo "Merging /boot/efi ($efi_dev) into the root filesystem"
    # Trailing digits of the device name are the partition number (PARTN is not
    # available on older util-linux).
    efi_partnum="${efi_dev##*[!0-9]}"
    rsync -aSH /boot/efi/ /boot_efi.new/
    umount /boot/efi
    blkdiscard "$efi_dev" || true
    rsync -aSH /boot_efi.new/ /boot/efi/
    rm -rf /boot_efi.new
    parted "/dev/$root_disk" -s "rm $efi_partnum"
fi
# Remove any bios_grub stub partition (GPT type 21686148-6449-6e6f-744e-656564454649).
lsblk -nro NAME,PARTTYPE "/dev/$root_disk" | while read -r part parttype; do
    if [ "$parttype" = "21686148-6449-6e6f-744e-656564454649" ]; then
        echo "Removing bios_grub stub partition /dev/$part"
        blkdiscard "/dev/$part" || true
        parted "/dev/$root_disk" -s "rm ${part##*[!0-9]}"
    fi
done

### Phase 5: Download-only steps (cached on the image for deploy time) ###

# ZFS + matching headers from backports (to match the backported kernel), and
# GRUB for both firmware types; make_image_bootable.sh installs the right one.
apt-get install --no-install-recommends --download-only -y -t bookworm-backports \
    linux-headers-amd64 zfs-dkms zfs-initramfs zfs-zed
apt-get install --no-install-recommends --download-only -y grub-efi-amd64
apt-get install --no-install-recommends --download-only -y grub-pc

### Phase 6: Cloud-init tuning ###

# growpart/resizefs resize partitions on first boot and can break custom storage
# layouts; grub-dpkg records an incorrect GRUB boot disk (PUBM-22667).
disable_cloud_init_module growpart
disable_cloud_init_module resizefs
disable_cloud_init_module 'grub[_-]dpkg'

### Phase 7: Image cleanup ###

apt-get purge -y '?config-files'
rm -rf /root/.cache
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
cloud-init clean
rm -f /etc/machine-id
