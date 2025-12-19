#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Remove "PasswordAuthentication yes" that cloud-init enabled because of "ssh_pwauth: true"
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf

# sources.list is created by cloud-init during the configure stage (apt-configure),
# after SSH configuration (ssh), which is done during the init stage.
# Therefore we need to wait for cloud-init to finish before running apt commands.
# Failure to do so will cause apt to randomly fail because of missing packages - PUBM-16450.
cloud-init status --wait

# Install packages and updates
apt-get -y update
apt-get -y dist-upgrade

# P8H77-M and D425KT boards have NICs which require the r8169 module - PUBM-16807 + PUBM-17155
# On Ubuntu, this module is included in a separate linux-modules-extra package
# The only way to pull linux-modules-extra and keep it up-to-date is to rely on this metapackage
# Don't install recommends to skip "thermald" which pulls more dependencies

# First, remove the existing kernels
apt-get purge -y "linux-image-*"
# Then, install the HWE one
apt-get install -y --no-install-recommends linux-generic-hwe-20.04

# Purge grub-pc now to make sure that it doesn't stay in a "rc" state on UEFI servers.
# Remove grub-efi-amd64-signed because its postinst script doesn't honour grub2/update_nvram.
# Upstream bug report about that: https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1969845
# Same problem with shim-signed
# Remove the linux-image-virtual kernel because we installed the generic one
apt-get -y purge grub-efi-amd64-signed grub-pc linux-image-virtual shim-signed --allow-remove-essential

# Create a default GRUB config file based on the default because purging grub-pc
# removed the existing one, this needs to be done before autoremove removes grub2-common.
cat << 'EOF' > /etc/default/grub
# This file is based on /usr/share/grub/default/grub, some settings
# have been changed by OVHcloud.

EOF
sed -E \
  -e 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="nomodeset iommu=pt"|g' \
  -e 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=""|' \
  /usr/share/grub/default/grub >> /etc/default/grub

apt-get -y autoremove
# Purge all packages left in "rc" state - see "man apt-patterns".
apt-get -y purge '?config-files'
apt-get -y clean

# Download GRUB for legagy and UEFI servers, both can't be installed simultaneously - PUBM-22671.
apt-get -y install --download-only grub-efi-amd64
apt-get -y install --download-only grub-pc

# Make sure grub-efi-amd64 won't change the boot order.
echo "grub-efi-amd64 grub2/update_nvram boolean false" | debconf-set-selections

# Disable some cloud-init options:
# grub-dpkg sets an incorrect value to "grub-pc/install_devices" - PUBM-22667.
# growpart and resizefs are not needed and can cause problems with ZFS partitions.
sed -Ei '/^  - (grub-dpkg|growpart|resizefs)/d' /etc/cloud/cloud.cfg

# Remove hardcoded console-related parameters
rm -f /etc/default/grub.d/50-cloudimg-settings.cfg

# Remove old machine-id
rm -f /etc/machine-id
