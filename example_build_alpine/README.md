# Alpine Linux Build Example

This directory contains a Packer configuration for building an Alpine Linux image suitable for OVHcloud baremetal servers.

## Files

- `alpine.pkr.hcl` - Main Packer configuration file in HCL format
- `provision.sh` - Script to prepare the Alpine Linux system for baremetal deployment
- `make_image_bootable.sh` - Script to make the image bootable on OVHcloud baremetal servers

## Building the Image

To build the image, run:

```bash
packer build alpine.pkr.hcl
```

The resulting image will be located in the `output/` directory.

## Configuration Details

This build uses:
- Alpine Linux v3.20.1 (latest stable release)
- QEMU builder for virtualization
- Cloud-init for initial configuration
- GRUB bootloader configured for baremetal boot
- Support for RAID, LVM, and various filesystems
- Intel and AMD microcode support

## Requirements

- Packer 1.7+
- QEMU/KVM support
- At least 4GB RAM for building