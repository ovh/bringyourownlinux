packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "baremetal" {
  # Arch Linux cloud image (rolling). provision.sh installs the bare-metal
  # tooling and collapses the image to a single partition.
  iso_url      = "https://archlinux.mirrors.ovh.net/archlinux/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
  iso_checksum = "file:https://archlinux.mirrors.ovh.net/archlinux/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
  disk_image   = true
  # Grow the ~2G source so the system upgrade plus firmware/microcode packages
  # do not fill the disk.
  disk_size = "4G"

  format           = "qcow2"
  vm_name          = "archlinux.qcow2"
  output_directory = "output"
  disk_compression = true
  # Expose discard so blkdiscard in the single-partition step trims freed blocks.
  disk_discard = "unmap"

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
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    script          = "provision.sh"
  }
}
