packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "baremetal" {
  # Ubuntu 20.04 (focal) cloud image. The 5.15 HWE kernel is installed by
  # provision.sh.
  iso_url      = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  iso_checksum = "file:https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
  disk_image   = true
  # Room for the HWE kernel plus the cached GRUB packages.
  disk_size = "6G"

  format           = "qcow2"
  vm_name          = "ubuntu-20.04-kernel-5.15.qcow2"
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

  shutdown_command = "sudo poweroff"

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
    source      = "make_image_bootable.sh"
    destination = "/tmp/make_image_bootable.sh"
  }

  provisioner "shell" {
    execute_command  = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    script           = "provision.sh"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }
}
