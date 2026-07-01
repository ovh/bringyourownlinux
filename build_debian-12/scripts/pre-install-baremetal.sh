#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# This forces GRUB to use PARTUUID instead of UUID for root=, which does not
# work for us, see
# https://salsa.debian.org/cloud-team/debian-cloud-images/-/merge_requests/388
rm -f /etc/default/grub.d/10_cloud.cfg

# grub-cloud can cause problems after the server is installed
# purge the old kernels
apt-get -y purge grub-cloud-amd64 linux-image-*
# Restore a default grub config as the old file belonged to grub-cloud-amd64 and got removed
# by the purge.
# Copying /usr/share/grub/default/grub to /etc/default/grub is otherwise done by
# grub-pc or grub-efi-amd64's postinst.
cp /usr/share/grub/default/grub /etc/default/grub

# Enable contrib + non-free (ZFS) and non-free-firmware (AMD/Intel microcodes),
# and add bookworm-backports to pull the latest Debian kernel. Handle both the
# deb822 (.sources) layout used by recent cloud images and the legacy one-line
# sources.list, so this keeps working whichever the base image ships.
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

# Install the latest kernel from backports
apt-get -y install --no-install-recommends -t bookworm-backports linux-image-amd64

apt-get -y install --no-install-recommends mdadm lvm2 btrfs-progs amd64-microcode intel-microcode rsync parted
# We will install these in make_image_bootable.sh and only when ZFS is used.
# Pull them from backports so the headers and ZFS module match the backported
# kernel installed above. linux-headers-amd64 needs to be manually specified
# because dkms only recommends it.
apt-get -y install --no-install-recommends --download-only -t bookworm-backports \
    linux-headers-amd64 zfs-dkms zfs-initramfs zfs-zed
apt-get -y dist-upgrade

# Cleanup
apt-get -y autoremove
apt-get -y clean

### Make the image single-partition (BYOL requirement) ###
# The generic cloud image ships an ESP and a bios_grub stub alongside the Linux
# root partition, but BYOL requires a single partition. Merge the ESP into the
# root filesystem and delete the extra partitions; the target's real ESP is
# recreated by OVHcloud partitioning and make_image_bootable.sh reinstalls GRUB
# there at deploy time. blkdiscard before parted rm releases the freed blocks in
# the qcow2 instead of leaving them allocated.
root_disk="$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")"
efi_dev="$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)"
if [ -n "$efi_dev" ]; then
    echo "Merging /boot/efi ($efi_dev) into the root filesystem"
    efi_partnum="$(lsblk -no PARTN "$efi_dev")"
    rsync -aSH /boot/efi/ /boot_efi.new/
    umount /boot/efi
    blkdiscard "$efi_dev"
    rsync -aSH /boot_efi.new/ /boot/efi/
    rm -rf /boot_efi.new
    parted "/dev/$root_disk" -s "rm $efi_partnum"
fi
# Remove any bios_grub stub partition (GPT type 21686148-6449-6e6f-744e-656564454649).
lsblk -nro NAME,PARTTYPE "/dev/$root_disk" | while read -r part parttype; do
    if [ "$parttype" = "21686148-6449-6e6f-744e-656564454649" ]; then
        echo "Removing bios_grub stub partition /dev/$part"
        blkdiscard "/dev/$part"
        parted "/dev/$root_disk" -s "rm $(lsblk -no PARTN "/dev/$part")"
    fi
done

# Download GRUB for legacy and UEFI servers, both can't be installed simultaneously.
apt-get -y install --no-install-recommends --download-only grub-efi-amd64
apt-get -y install --no-install-recommends --download-only grub-pc
# Make sure grub-efi-amd64 won't change the boot order.
echo "grub-efi-amd64 grub2/update_nvram boolean false" | debconf-set-selections

# Disable some cloud-init options:
# grub-dpkg sets an incorrect value to "grub-pc/install_devices".
# growpart and resizefs are not needed and can cause problems with ZFS partitions.
sed -Ei '/^ - (grub-dpkg|growpart|resizefs)/d' /etc/cloud/cloud.cfg

# Make ifupdown more verbose to help detect bugs/misconfigurations
#sed -i 's/^#VERBOSE=.*/VERBOSE=yes/' /etc/default/networking

# Configure GRUB for baremetal boot. Use sed rather than a context patch so this
# stays robust across changes to Debian's default grub template.
sed -Ei \
    -e 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="nomodeset iommu=pt"|' \
    -e 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=""|' \
    /etc/default/grub
grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub \
    && sed -Ei 's|^GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX="text"|' /etc/default/grub \
    || echo 'GRUB_GFXPAYLOAD_LINUX="text"' >> /etc/default/grub

# Remove old machine-id
rm -f /etc/machine-id
