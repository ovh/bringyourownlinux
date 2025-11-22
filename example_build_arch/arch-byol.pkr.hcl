packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "arch_image_url" {
  type    = string
  default = "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
}

variable "arch_checksum_url" {
  type    = string
  default = "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
}

locals {
  packer_password = uuidv4()
}

source "qemu" "arch" {
  # cloud-init will use the CD as datasource, see https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html#source-2-drive-with-labeled-filesystem
  cd_label   = "cidata"
  cd_content = {
    "/meta-data" = <<-EOF
    instance-id: arch-byol-image
    local-hostname: archlinux
    EOF
    "/user-data" = <<-EOF
    #cloud-config
    ssh_pwauth: true
    users:
      - name: packer
        plain_text_passwd: ${local.packer_password}
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: wheel
        shell: /bin/bash
        lock_passwd: false

    # Ensure SSH is enabled and started
    runcmd:
      - systemctl enable sshd
      - systemctl start sshd

    # Network configuration
    bootcmd:
      - dhclient || dhcpcd
    EOF
  }

  iso_url          = var.arch_image_url
  iso_checksum     = "file:${var.arch_checksum_url}"
  disk_image       = true
  disk_size        = "5G"
  disk_compression = true
  format           = "qcow2"
  headless         = true

  communicator              = "ssh"
  ssh_username              = "packer"
  ssh_password              = local.packer_password
  ssh_clear_authorized_keys = true
  ssh_timeout               = "20m"

  # Before shutting down, truncate logs
  shutdown_command = "sudo sh -c 'find /var/log/ -type f -exec truncate --size 0 {} + && rm -f /etc/sudoers.d/90-cloud-init-users && userdel -fr packer && poweroff'"

  output_directory = "output"
  vm_name          = "arch-byol.qcow2"

  qemuargs = [
    ["-m", "2048"],
    ["-smp", "2"],
    ["-serial", "stdio"]
  ]
}

build {
  sources = ["source.qemu.arch"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    inline = [
      "#!/bin/bash",
      "set -euo pipefail",
      "",
      "# This script prepares an Arch Linux cloud image for OVH baremetal servers",
      "",
      "# Update the system and install necessary packages for baremetal deployment",
      "pacman -Syu --noconfirm",
      "",
      "# Install packages needed for baremetal deployment:",
      "# - mdadm: software RAID support",
      "# - lvm2: logical volume management",
      "# - btrfs-progs: Btrfs filesystem support",
      "# - dosfstools: FAT filesystem support (needed for EFI partitions)",
      "# - grub: bootloader",
      "# - efibootmgr: UEFI boot manager",
      "# - intel-ucode, amd-ucode: CPU microcode updates",
      "pacman -S --noconfirm --needed \\",
      "    mdadm \\",
      "    lvm2 \\",
      "    btrfs-progs \\",
      "    dosfstools \\",
      "    grub \\",
      "    efibootmgr \\",
      "    intel-ucode \\",
      "    amd-ucode \\",
      "    linux \\",
      "    linux-headers",
      "",
      "# Configure GRUB defaults for baremetal servers",
      "# Remove quiet mode and add necessary kernel parameters",
      "if [ -f /etc/default/grub ]; then",
      "    # Backup original config",
      "    cp /etc/default/grub /etc/default/grub.bak",
      "",
      "    # Update GRUB configuration for baremetal",
      "    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' /etc/default/grub",
      "    sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset iommu=pt\"/' /etc/default/grub",
      "",
      "    # Add text mode for better compatibility",
      "    if ! grep -q '^GRUB_GFXPAYLOAD_LINUX' /etc/default/grub; then",
      "        echo 'GRUB_GFXPAYLOAD_LINUX=\"text\"' >> /etc/default/grub",
      "    else",
      "        sed -i 's/GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX=\"text\"/' /etc/default/grub",
      "    fi",
      "",
      "    # Ensure GRUB timeout is reasonable",
      "    sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub",
      "fi",
      "",
      "# Configure mkinitcpio for baremetal (disable autodetect to include all drivers)",
      "if [ -f /etc/mkinitcpio.conf ]; then",
      "    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak",
      "",
      "    # IMPORTANT: Include mdadm_udev for RAID support (RAID 0, RAID 1, etc)",
      "    # Remove autodetect hook - we need ALL drivers for baremetal",
      "    sed -i 's/^HOOKS=.*/HOOKS=(base systemd modconf kms keyboard sd-vconsole block mdadm_udev filesystems fsck)/' /etc/mkinitcpio.conf",
      "",
      "    # Add NVMe, SATA, and RAID modules explicitly",
      "    sed -i 's/^MODULES=.*/MODULES=(nvme nvme_core ahci sd_mod md_mod raid0 raid1 raid10 raid456)/' /etc/mkinitcpio.conf",
      "",
      "    # Regenerate initramfs with all modules including RAID",
      "    mkinitcpio -P",
      "fi",
      "",
      "# Enable necessary services for baremetal",
      "systemctl enable sshd",
      "systemctl enable systemd-networkd",
      "systemctl enable systemd-resolved",
      "",
      "# Configure mdadm if config exists",
      "if [ -f /etc/mdadm.conf ]; then",
      "    # Backup and regenerate mdadm configuration",
      "    mv /etc/mdadm.conf /etc/mdadm.conf.bak || true",
      "fi",
      "",
      "# Remove machine-id so a new one will be generated on first boot",
      "rm -f /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "",
      "# Clean package cache",
      "pacman -Scc --noconfirm || true",
      "",
      "echo 'Arch Linux baremetal preparation completed successfully'"
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    inline = [
      "mkdir -p /root/.ovh/",
      "cat > /root/.ovh/make_image_bootable.sh <<'MAKE_BOOTABLE_EOF'",
      "#!/bin/bash",
      "",
      "# Licensed under the Apache License, Version 2.0 (the \"License\"); you may not use this",
      "# file except in compliance with the License. You may obtain a copy of the License at",
      "# http://www.apache.org/licenses/LICENSE-2.0",
      "# Unless required by applicable law or agreed to in writing, software distributed under",
      "# the License is distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF",
      "# ANY KIND, either express or implied. See the License for the specific language",
      "# governing permissions and limitations under the License.",
      "",
      "###########################################################",
      "# This script makes an Arch Linux image bootable on OVH  #",
      "# baremetal servers after deployment                      #",
      "###########################################################",
      "",
      "# Only exit on critical failures, allow some commands to fail",
      "set -e",
      "",
      "# Get console parameters from rescue's cmdline",
      "console_parameters=\"\\$(grep -Po '\\bconsole=\\S+' /proc/cmdline | paste -s -d\" \" || true)\"",
      "if [ -n \"\\$console_parameters\" ] && [ -f /etc/default/grub ]; then",
      "    if ! grep -q \"\\$console_parameters\" /etc/default/grub 2>/dev/null; then",
      "        sed -Ei \"s/(^GRUB_CMDLINE_LINUX=.*)\\\"\\$/\\1 \\$console_parameters\\\"/\" /etc/default/grub || true",
      "    fi",
      "fi",
      "",
      "# Configure mkinitcpio hooks for RAID if needed",
      "if [ -e /proc/mdstat ] && grep -q md /proc/mdstat 2>/dev/null; then",
      "    if [ -f /etc/mkinitcpio.conf ]; then",
      "        if ! grep -q mdadm_udev /etc/mkinitcpio.conf; then",
      "            sed -i 's/^HOOKS=(\\(.*\\)block/HOOKS=(\\1block mdadm_udev/' /etc/mkinitcpio.conf || true",
      "        fi",
      "    fi",
      "fi",
      "",
      "# Detect boot mode and install GRUB",
      "if [ -d /sys/firmware/efi ]; then",
      "    # UEFI mode",
      "    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --no-nvram",
      "else",
      "    # BIOS mode",
      "    # Find the root device",
      "    root_device=\\$(findmnt -n -o SOURCE / | head -1)",
      "",
      "    if [[ \"\\$root_device\" =~ /dev/md ]]; then",
      "        # RAID: install to all member disks",
      "        for disk in \\$(lsblk -ndo PKNAME \"\\$root_device\" | sort -u); do",
      "            grub-install --target=i386-pc \"/dev/\\$disk\" || true",
      "        done",
      "    else",
      "        # Single disk: find parent disk",
      "        disk_device=\\$(lsblk -npo PKNAME \"\\$root_device\" | head -1)",
      "        if [ -n \"\\$disk_device\" ]; then",
      "            grub-install --target=i386-pc \"\\$disk_device\"",
      "        fi",
      "    fi",
      "fi",
      "",
      "# Generate GRUB config",
      "grub-mkconfig -o /boot/grub/grub.cfg",
      "",
      "# Regenerate initramfs",
      "mkinitcpio -P",
      "",
      "# Generate unique machine-id",
      "systemd-machine-id-setup",
      "",
      "# Cleanup",
      "rm -fr /root/.ovh/",
      "",
      "exit 0",
      "MAKE_BOOTABLE_EOF",
      "chmod +x /root/.ovh/make_image_bootable.sh"
    ]
  }

  # Clean up packer user on first boot via systemd service
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    inline = [
      "echo 'Creating cleanup service for packer user...'",
      "tee /etc/systemd/system/packer-cleanup.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Remove packer user on first boot",
      "After=cloud-init.service",
      "ConditionPathExists=!/var/lib/packer-cleanup-done",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/bin/userdel -r packer",
      "ExecStartPost=/usr/bin/touch /var/lib/packer-cleanup-done",
      "RemainAfterExit=yes",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "systemctl enable packer-cleanup.service",
      "echo 'Packer user will be removed on first boot'"
    ]
  }
}
