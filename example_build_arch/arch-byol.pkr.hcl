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

# Stage 1: Generate cloud-init ISO
source "file" "cidata" {
  content = "dummy"
  target  = "dummy_file"
}

# Stage 2: Build the actual image
source "qemu" "arch" {
  iso_url      = var.arch_image_url
  iso_checksum = "file:${var.arch_checksum_url}"
  disk_image   = true
  disk_size    = "5G"
  disk_compression = true
  format       = "qcow2"
  headless     = true
  boot_wait    = "-1s"

  communicator = "ssh"
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_clear_authorized_keys = true
  ssh_timeout  = "20m"

  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"

  output_directory = "output"
  vm_name         = "arch-byol.qcow2"

  qemuargs = [
    ["-m", "2048"],
    ["-smp", "2"],
    ["-cdrom", "cidata.iso"],
    ["-netdev", "user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net,netdev=user.0"]
  ]
}

build {
  name = "10_generator"
  sources = ["source.file.cidata"]

  provisioner "shell-local" {
    inline_shebang = "/bin/bash -xe"
    inline = [
      "cd httpdir && genisoimage -output ../cidata.iso -input-charset utf-8 -volid cidata -joliet -r user-data meta-data"
    ]
  }
}

build {
  name = "20_builder"
  sources = ["source.qemu.arch"]

  provisioner "shell" {
    script          = "scripts/pre-install-baremetal.sh"
    execute_command = "chmod +x {{ .Path }} && sudo {{ .Path }}"
  }

  provisioner "file" {
    source      = "files/make_image_bootable.sh"
    destination = "/tmp/make_image_bootable.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo -S mkdir -p /root/.ovh/",
      "sudo -S mv /tmp/make_image_bootable.sh /root/.ovh/",
      "sudo -S chmod -R +x /root/.ovh/"
    ]
    pause_before = "5s"
  }

  # Clean up packer user on first boot via systemd service
  provisioner "shell" {
    inline = [
      "echo 'Creating cleanup service for packer user...'",
      "sudo tee /etc/systemd/system/packer-cleanup.service > /dev/null <<'EOF'",
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
      "sudo systemctl enable packer-cleanup.service",
      "echo 'Packer user will be removed on first boot'"
    ]
  }
}
