# Alpine Linux BYOL image

Packer example that builds a Bring Your Own Linux (BYOL) compatible Alpine image
for OVHcloud bare-metal servers.

## What it builds

- **Base image:** Alpine 3.22 cloud image (`nocloud_alpine-3.22.1-x86_64-bios-cloudinit-metal`)
- **Kernel:** Alpine `linux-lts`
- **Output:** `output/alpine.qcow2`
- Single ext4 root partition, cloud-init enabled, with
  `/root/.ovh/make_image_bootable.sh` embedded.

## EFI bootloader path

On a UEFI server, `make_image_bootable.sh` installs GRUB to the EFI System
Partition at:

```
\EFI\alpine\grubx64.efi
```

This is the path of the EFI bootloader in the OS installed on the server; use it
if a deployment/reinstall needs the EFI bootloader location. On legacy BIOS
servers, GRUB is written to the MBR of the boot disk(s) instead.

## Build

```bash
packer init alpine.pkr.hcl
PACKER_LOG=1 packer build alpine.pkr.hcl
```

> Alpine publishes no "latest" symlink for cloud images, so the version is pinned
> in `alpine.pkr.hcl` and must be bumped explicitly (Renovate can track it).
