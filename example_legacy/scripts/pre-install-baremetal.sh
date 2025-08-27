#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# This forces GRUB to use PARTUUID instead of UUID for root=, which does not
# work for us, see
# https://salsa.debian.org/cloud-team/debian-cloud-images/-/merge_requests/388
rm /etc/default/grub.d/50-cloudimg-settings.cfg
# Add contrib to allow ZFS installation
# Add non-free-firmware for AMD and Intel microcodes
sed -i "s/\bmain\b/& restricted multiverse universe/" /etc/apt/sources.list
apt-get update
# Install the 5.4 HWE kernel
apt-get -y install --no-install-recommends linux-image-5.4.0-42-generic linux-headers-5.4.0-42-generic
# Hold the kernel packages to prevent updates
apt-mark hold linux-image-5.4.0-42-generic linux-headers-5.4.0-42-generic linux-image-generic-hwe-20.04 linux-headers-generic-hwe-20.04
apt-get -y install --no-install-recommends mdadm lvm2 patch btrfs-progs amd64-microcode intel-microcode
# We will install these in make_image_bootable.sh and only when ZFS is used
# linux-headers-generic needs to be manually specified because dkms only recommends it
apt-get -y install --no-install-recommends --download-only linux-headers-5.4.0-42-generic zfs-dkms zfsutils-linux
apt-get -y dist-upgrade
# Cleanup
apt-get -y autoremove
apt-get -y clean
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

# Instead of using patch, let's directly modify the grub configuration
# Backup the original file
cp /etc/default/grub /etc/default/grub.bak

# Directly modify the GRUB configuration
cat > /etc/default/grub << 'EOF'
# This file is based on /usr/share/grub/default/grub, some settings
# have been changed by OVHcloud.

# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.
# For full documentation of the options in this file, see:
#   info -f grub -n 'Simple configuration'

GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="nomodeset iommu=pt"
GRUB_GFXPAYLOAD_LINUX="text"

# Uncomment to enable BadRAM filtering, modify to suit your needs
# This works with Linux (no patch required) and with any kernel that obtains
# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)
#GRUB_BADRAM="0x01234567,0xfefefefe,0x89abcdef,0xefefefef"

# Uncomment to disable graphical terminal (grub-pc only)
#GRUB_TERMINAL=console

# The resolution used on graphical terminal
# note that you can use only modes which your graphic card supports via VBE
# you can see them in real GRUB with the command `vbeinfo'
#GRUB_GFXMODE=640x480

# Uncomment if you don't want GRUB to pass "root=UUID=xxx" parameter to Linux
#GRUB_DISABLE_LINUX_UUID=true

# Uncomment to disable generation of recovery mode menu entries
#GRUB_DISABLE_RECOVERY="true"

# Uncomment to get a beep at grub start
#GRUB_INIT_TUNE="480 440 1"
EOF

# Remove old machine-id
rm -f /etc/machine-id