packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "baremetal" {
  # Official Alpine cloud image: BIOS firmware + cloud-init + bare-metal variant.
  # Alpine has no "latest" symlink for cloud images, so the version is pinned and
  # bumped explicitly (Renovate-friendly). provision.sh collapses the image to a
  # single partition.
  iso_url      = "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal-r0.qcow2"
  iso_checksum = "file:https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal-r0.qcow2.sha512"
  disk_image   = true
  disk_size    = "3G"

  format           = "qcow2"
  vm_name          = "alpine.qcow2"
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

  # BusyBox tools: remove the provisioning user (known password) before halting.
  shutdown_command = "sudo sh -c 'deluser packer 2>/dev/null; rm -rf /home/packer; poweroff'"

  # Serial to stdout so boot messages appear in the Packer log (PACKER_LOG=1).
  qemuargs = [["-serial", "stdio"]]

  # cloud-init NoCloud seed. The Alpine cloud image ships without sudo, but
  # Packer runs the provisioner via sudo, so cloud-init installs it on first boot.
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-USERDATA
    #cloud-config
    ssh_pwauth: true
    packages:
      - sudo
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

  # Wait for cloud-init to finish (so sudo from the seed's package list is
  # installed) before the sudo-based provisioner runs. Runs as the packer user.
  provisioner "shell" {
    inline = ["cloud-init status --wait || true"]
  }

  provisioner "file" {
    source      = "make_image_bootable.sh"
    destination = "/tmp/make_image_bootable.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    script          = "provision.sh"
  }
}
