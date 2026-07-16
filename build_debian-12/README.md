# Debian 12 BYOL image

Packer example that builds a Bring Your Own Linux (BYOL) compatible Debian 12
(bookworm) image for OVHcloud bare-metal servers, running the latest backported
kernel.

## What it builds

- **Base image:** Debian 12 generic cloud image (`debian-12-generic-amd64.qcow2`)
- **Kernel:** latest `linux-image-amd64` from `bookworm-backports`
- **Output:** `output/debian-12.qcow2`
- Single ext4 root partition, cloud-init enabled, with
  `/root/.ovh/make_image_bootable.sh` embedded.

## EFI bootloader path

On a UEFI server, `make_image_bootable.sh` installs GRUB to the EFI System
Partition at:

```
\EFI\debian\grubx64.efi
```

This is the path of the EFI bootloader in the OS installed on the server; use it
if a deployment/reinstall needs the EFI bootloader location. On legacy BIOS
servers, GRUB is written to the MBR of the boot disk(s) instead.

## Build

```bash
packer init debian-12.pkr.hcl
PACKER_LOG=1 packer build debian-12.pkr.hcl
```
