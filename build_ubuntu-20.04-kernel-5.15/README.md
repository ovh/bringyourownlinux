# Ubuntu 20.04 BYOL image

Packer example that builds a Bring Your Own Linux (BYOL) compatible Ubuntu 20.04
(focal) image for OVHcloud bare-metal servers, running the 5.15 HWE kernel.

## What it builds

- **Base image:** Ubuntu 20.04 cloud image (`focal-server-cloudimg-amd64.img`)
- **Kernel:** `linux-generic-hwe-20.04` (5.15)
- **Output:** `output/ubuntu-20.04-kernel-5.15.qcow2`
- Single ext4 root partition, cloud-init enabled, with
  `/root/.ovh/make_image_bootable.sh` embedded.

## EFI bootloader path

On a UEFI server, `make_image_bootable.sh` installs GRUB to the EFI System
Partition at:

```
\EFI\ubuntu\grubx64.efi
```

This is the path of the EFI bootloader in the OS installed on the server; use it
if a deployment/reinstall needs the EFI bootloader location. On legacy BIOS
servers, GRUB is written to the MBR of the boot disk(s) instead.

## Build

```bash
packer init ubuntu-20.04-kernel-5.15.pkr.hcl
PACKER_LOG=1 packer build ubuntu-20.04-kernel-5.15.pkr.hcl
```
