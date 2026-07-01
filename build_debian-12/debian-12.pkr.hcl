packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "baremetal" {
  # Debian 12 (bookworm) generic cloud image. The backported kernel is installed
  # by provision.sh.
  iso_url      = "https://cdimage.debian.org/cdimage/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  iso_checksum = "file:https://cdimage.debian.org/cdimage/cloud/bookworm/latest/SHA512SUMS"
  disk_image   = true
  # Room for the newer kernel plus the cached ZFS/GRUB packages.
  disk_size = "5G"

  format           = "qcow2"
  vm_name          = "debian-12.qcow2"
  output_directory = "output"
  disk_compression = true

  accelerator = "kvm"
  cpus        = 2
  memory      = 2048
  headless    = true

  communicator              = "ssh"
  ssh_username              = "packer"
  ssh_password              = "packer"
  ssh_clear_authorized_keys = true
  ssh_timeout               = "5m"

  # Remove the provisioning user (known password) before powering off.
  shutdown_command = "sudo sh -c 'userdel -rf packer 2>/dev/null; poweroff'"

  # Serial to stdout so boot messages appear in the Packer log (PACKER_LOG=1).
  qemuargs = [["-serial", "stdio"]]

  # cloud-init NoCloud seed: create the provisioning user from the CD.
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-USERDATA
    #cloud-config
    ssh_pwauth: true
    users:
      - name: packer
        plain_text_passwd: packer
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
        shell: /bin/bash
    USERDATA
  }
  cd_label = "cidata"
}

build {
  sources = ["source.qemu.baremetal"]

  provisioner "file" {
    source      = "files/make_image_bootable.sh"
    destination = "/tmp/make_image_bootable.sh"
  }

  provisioner "shell" {
    execute_command  = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    script           = "scripts/pre-install-baremetal.sh"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }
}
