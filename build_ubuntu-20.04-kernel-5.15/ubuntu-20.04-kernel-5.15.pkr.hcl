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
    users:
      - name: packer
        plain_text_passwd: packer
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
    EOF
  }
  # Enabling this makes the build much longer but halves the image size
  disk_compression          = true
  # The source is a disk image, not an ISO file
  disk_image                = true
  # Required for the new kernel to fit into the image
  disk_size                 = "5G"
  format                    = "qcow2"
  # Do not launch QEMU's GUI
  headless                  = true
  iso_checksum              = "file:https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
  iso_url                   = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  # Allows us to see the VM's console when PACKER_LOG=1 is set
  qemuargs                  = [["-serial", "stdio"]]
  # Before shutting down, truncate logs and remove everything linked to the provisioning user
  shutdown_command          = "sudo sh -c 'find /var/log/ -type f -exec truncate --size 0 {} + && rm -f /etc/sudoers.d/90-cloud-init-users && userdel -fr packer && poweroff'"
  communicator              = "ssh"
  ssh_clear_authorized_keys = true
  ssh_username              = "packer"
  ssh_password              = "packer"
  # The resulting image will be written to output/ubuntu2004-kernel-5.15.qcow2
  output_directory          = "output"
  vm_name                   = "ubuntu-20.04-kernel-5.15.qcow2"
}

build {
  sources = ["source.qemu.builder"]

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
