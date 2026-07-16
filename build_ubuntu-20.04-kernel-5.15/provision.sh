#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# cloud-init writes the apt sources during its configure stage; apt commands
# racing it fail randomly with missing packages (PUBM-16450). Exit code 2 is a
# recoverable warning and is tolerated.
cloud_init_status=0
cloud-init status --wait || cloud_init_status=$?
if [ "$cloud_init_status" != 0 ] && [ "$cloud_init_status" != 2 ]; then
    echo "cloud-init status exited with invalid code $cloud_init_status" >&2
    exit 1
fi

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

# 50-cloudimg-settings.cfg forces ttyS0 console and net.ifnames=0 for cloud
# environments; on bare-metal these misdetect the console and interface names.
rm -f /etc/default/grub.d/50-cloudimg-settings.cfg
# grub-efi-amd64-signed / shim-signed postinsts modify the EFI boot order and do
# not honor grub2/update_nvram (LP: #1969845); OVHcloud servers boot over the
# network. grub-pc must be purged so its install on the target is a FRESH one
# (only then does its postinst write MBR boot code). linux-image-virtual lacks
# linux-modules-extra (e.g. r8169 NICs - PUBM-16807/17155); the HWE kernel below
# replaces it.
apt-get purge --allow-remove-essential -y \
    grub-efi-amd64-signed shim-signed grub-pc linux-image-virtual

cp /usr/share/grub/default/grub /etc/default/grub
# nomodeset: KVM display on some boards (PUBM-22537).
# iommu=pt: avoids AMD kernel panics under load (PUBM-15188).
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="nomodeset iommu=pt"/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub

echo 'grub-efi-amd64 grub2/update_nvram boolean false' | debconf-set-selections

### Phase 2: Repository configuration ###

# During a build the machine-id is ephemeral, so phased-rollout may randomly
# defer packages. Force all phased updates in so the image is fully up to date.
echo 'APT::Get::Always-Include-Phased-Updates "true";' \
    > /etc/apt/apt.conf.d/99-disable-phased-updates
apt-get update

### Phase 3: Package installation ###

# linux-generic-hwe-20.04 provides the 5.15 kernel and depends on
# linux-modules-extra (full NIC/storage driver set). ZFS userland is installed
# so no DKMS build is needed at customer install time (the module ships with the
# HWE kernel's linux-modules).
apt-get install --no-install-recommends -y \
    linux-generic-hwe-20.04 \
    mdadm lvm2 btrfs-progs xfsprogs dosfstools rsync parted \
    amd64-microcode intel-microcode linux-firmware \
    zfsutils-linux zfs-zed zfs-initramfs
# Import pools at boot when / is not ZFS (the initramfs handles ZFS-root).
systemctl enable zfs-import-scan.service
apt-get dist-upgrade -y

### Phase 4: Cleanup (before the download-only steps so those persist) ###

apt-get autoremove --purge -y
apt-get clean

### Phase 4.5: Single-partition image (BYOL requires exactly one partition) ###
# Merge any separate /boot and ESP into the root filesystem, then delete the
# extra partitions; the target's real ESP is recreated by OVHcloud partitioning
# and make_image_bootable.sh reinstalls GRUB there at deploy time. blkdiscard
# before parted rm so the freed blocks are actually released in the qcow2.
root_disk="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")"
efi_dev="$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)"
boot_dev="$(findmnt -n -o SOURCE /boot 2>/dev/null || true)"
efi_partnum=""
if [ -n "$efi_dev" ]; then
    echo "Staging /boot/efi ($efi_dev)"
    # Trailing digits of the device name are the partition number (PARTN is not
    # available on older util-linux).
    efi_partnum="${efi_dev##*[!0-9]}"
    rsync -aSH /boot/efi/ /boot_efi.new/
    umount /boot/efi
    blkdiscard "$efi_dev" || true
fi
if [ -n "$boot_dev" ]; then
    echo "Merging /boot ($boot_dev) into the root filesystem"
    boot_partnum="${boot_dev##*[!0-9]}"
    rsync -aHAX /boot/ /boot.new/
    umount /boot
    rmdir /boot
    mv /boot.new /boot
    if [ -n "$efi_dev" ]; then
        mkdir -p /boot/efi
        rsync -aSH /boot_efi.new/ /boot/efi/
        rm -rf /boot_efi.new
    fi
    blkdiscard "$boot_dev" || true
    [ -n "$efi_partnum" ] && parted "/dev/$root_disk" -s "rm $efi_partnum"
    parted "/dev/$root_disk" -s "rm $boot_partnum"
elif [ -n "$efi_dev" ]; then
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

# GRUB for both firmware types; make_image_bootable.sh installs the right one.
apt-get install --no-install-recommends --download-only -y grub-efi-amd64
apt-get install --no-install-recommends --download-only -y grub-pc
# Restore the default phased-update behaviour for the deployed server.
rm -f /etc/apt/apt.conf.d/99-disable-phased-updates

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
rm -f /etc/netplan/*.yaml
cloud-init clean
rm -f /etc/machine-id
