# Alpine Linux build example

This directory contains a Packer configuration for building an Alpine Linux image
suitable for OVHcloud baremetal servers.

## Files

- `alpine.pkr.hcl` - Packer configuration (HCL format)
- `provision.sh` - prepares the Alpine system for baremetal deployment
- `make_image_bootable.sh` - installed into `/root/.ovh/`, runs at install time to
  make the image bootable on OVHcloud baremetal servers

## Building the image

```bash
packer init alpine.pkr.hcl
PACKER_LOG=1 packer build alpine.pkr.hcl
```

The resulting image is written to `output/alpine.qcow2`.

## Configuration details

This build starts from the official Alpine **cloud** image (BIOS + cloud-init +
bare-metal variant) rather than the installer ISO, so cloud-init can bring up the
provisioning user from the `cidata` drive, exactly like the other builds in this
repository.

It uses:

- Alpine Linux 3.22 (`nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal`)
- the QEMU Packer builder
- GRUB configured for both legacy and UEFI baremetal boot
- support for RAID, LVM, btrfs/xfs/ext4 filesystems
- Intel and AMD microcode

> Alpine does not publish a "latest" symlink for cloud images, so the version is
> pinned in `alpine.pkr.hcl` and must be bumped explicitly (Renovate can track it).

## Requirements

- Packer 1.7+
- QEMU with KVM acceleration
