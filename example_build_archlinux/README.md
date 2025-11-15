# Arch Linux BYOL Image Build

This directory contains all the necessary files to build an Arch Linux image compatible with OVHcloud's Bring Your Own Linux (BYOL) system.

## Prerequisites

Install the required tools on your system, for instance on Debian or Ubuntu:
1. Follow https://developer.hashicorp.com/packer/install to install Packer
2. Install additional requirements (QEMU to start the build VM, genisoimage to
   create a cloud-init CD image as datasource):
   ```bash
   apt install genisoimage qemu-system-x86
   ```

## Directory Structure

```none
example_build_archlinux/
├── archlinux.pkr.hcl # Packer configuration file
├── make_image_bootable.sh # Runs during installation
└── provision.sh # Provisions the image for bare metal
```

## Building the Image

1. Install Packer QEMU plugin (only needed once):
   ```bash
   packer init archlinux.pkr.hcl
   ```

2. Run Packer to build the image:
   ```bash
   packer build archlinux.pkr.hcl
   ```

   Or with verbose logging:
   ```bash
   PACKER_LOG=1 packer build archlinux.pkr.hcl
   ```

3. The resulting image will be in `output/archlinux.qcow2`

## Build Process

The build process consists of several steps:

1. **Download Base Image**: Downloads the official Arch Linux cloud image
2. **Generate Cloud-Init ISO**: Creates an ISO image containing cloud-init configuration
3. **Boot VM**: Starts a QEMU VM with the base image
4. **Provision**: Runs `provision.sh` to install required packages and perform changes to configuration files
5. **Install the make_image_bootable.sh Script**: Copies `make_image_bootable.sh` to `/root/.ovh/`
6. **Shutdown**: Deletes the provisioning user, gracefully shuts down the VM and compresses the image

## What make_image_bootable.sh Does

This script runs **after** the image is deployed to an OVHcloud baremetal server and **before the first boot**:

- Detects boot mode (UEFI vs BIOS)
- Installs GRUB to the appropriate location:
  - UEFI: Installs to the EFI System Partition
  - BIOS: Installs to all disks selected for installation
- Configures GRUB to set the kernel's console parameters obtained from the
  rescue environment (for Serial-over-LAN)
- Generates a unique machine-id
- Generates GRUB configuration
- Regenerates the initramfs


## Using the Image

### Upload the Image

Upload the generated `output/archlinux.qcow2` to a Web server accessible by OVHcloud's network.

### Deploy via OVHcloud API

Perform a `POST` call to the `/dedicated/server/{serviceName}/reinstall` [route](https://eu.api.ovh.com/console/?section=%2Fdedicated%2Fserver&branch=v1#post-/dedicated/server/-serviceName-/reinstall):
```json
{
  "operatingSystem": "byolinux_64",
  "customizations": {
    "hostname": "my-arch-server",
    "imageURL": "http://your-server/archlinux.qcow2",
    "efiBootloaderPath": "EFI\\arch\\grubx64.efi",
    "sshKey": "ssh-ed25519 AAAA…"
  }
}
```

### Access the Server

The default user name is `arch`, as defined in the official image's
`/etc/cloud/cloud.cfg`. The SSH key provided during installation can be used to
access the server.

### Known issues

The `mdmonitor` service fails at boot because `mdadm.conf` does not contain an email address or alert command:
```none
Dec 16 13:43:51 my-arch-server systemd[1]: Started MD array monitor.
Dec 16 13:43:51 my-arch-server systemd[1]: mdmonitor.service: Main process exited, code=exited, status=1/FAILURE
Dec 16 13:43:51 my-arch-server mdadm[1450]: mdadm: No mail address or alert command - not monitoring.
Dec 16 13:43:51 my-arch-server systemd[1]: mdmonitor.service: Failed with result 'exit-code'.
```
If you want to use this service to monitor md RAID arrays, you will need to update `mdadm.conf`.

## Related Documentation

- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Linux mkinitcpio](https://wiki.archlinux.org/title/Mkinitcpio)
- [mdadm on Arch Linux](https://wiki.archlinux.org/title/RAID)
- [Packer's QEMU builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
