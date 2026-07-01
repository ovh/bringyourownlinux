packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "builder" {
  # cloud-init will use the CD as datasource, see https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html#source-2-drive-with-labeled-filesystem
  cd_label                  = "cidata"
  cd_content                = {
    "/meta-data" = ""
    "/user-data" = <<-EOF
    #cloud-config
    ssh_pwauth: true
    # The Alpine cloud image ships without sudo, but Packer runs the provisioners
    # via sudo. cloud-init installs it on first boot, before provisioning.
    packages:
      - sudo
    users:
      - name: packer
        plain_text_passwd: packer
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
    EOF
  }
  # Enabling this makes the build longer but reduces the image size
  disk_compression          = true
  # The source is a disk image (cloud qcow2), not an ISO file
  disk_image                = true
  # The "metal" cloud image ships the linux-lts kernel and baremetal firmware;
  # leave headroom for the upgrade and the extra packages installed by provision.sh
  disk_size                 = "3G"
  format                    = "qcow2"
  # Do not launch QEMU's GUI
  headless                  = true
  # Official Alpine cloud image: BIOS firmware + cloud-init + bare-metal variant.
  # Alpine has no "latest" symlink for cloud images, so the version is pinned and
  # bumped explicitly (Renovate-friendly).
  iso_checksum              = "file:https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal-r0.qcow2.sha512"
  iso_url                   = "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal-r0.qcow2"
  # Allows us to see the VM's console when PACKER_LOG=1 is set
  qemuargs                  = [["-serial", "stdio"]]
  # Before shutting down, truncate logs and remove everything linked to the provisioning user
  # BusyBox tools: truncate uses -s (not --size); use ';' so poweroff always runs
  shutdown_command          = "sudo sh -c 'find /var/log/ -type f -exec truncate -s 0 {} + ; rm -f /etc/sudoers.d/90-cloud-init-users ; deluser packer 2>/dev/null ; rm -rf /home/packer ; poweroff'"
  communicator              = "ssh"
  ssh_clear_authorized_keys = true
  ssh_username              = "packer"
  ssh_password              = "packer"
  # The resulting image will be written to output/alpine.qcow2
  output_directory          = "output"
  vm_name                   = "alpine.qcow2"
}

build {
  sources = ["source.qemu.builder"]

  # Wait for cloud-init to finish (so sudo from the user-data "packages" list is
  # installed) before any sudo-based provisioner runs. This step runs as the
  # packer user without sudo.
  provisioner "shell" {
    inline = ["cloud-init status --wait || true"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
    script          = "provision.sh"
  }

  provisioner "file" {
    destination = "/tmp/make_image_bootable.sh"
    source      = "make_image_bootable.sh"
  }

  provisioner "shell" {
    inline = ["sudo sh -c 'mkdir /root/.ovh/ && mv /tmp/make_image_bootable.sh /root/.ovh/ && chmod -R +x /root/.ovh/'"]
  }
}
