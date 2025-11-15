# Arch Linux BYOL Image Build

This directory contains all the necessary files to build an Arch Linux image compatible with OVH's Bring Your Own Linux (BYOL) system.

## Prerequisites

Install the required tools on your Arch Linux system:

```bash
sudo pacman -S packer qemu-full cdrtools
```

## Directory Structure

```
example_build_arch/
├── arch-byol.pkr.hcl           # Packer configuration file (HCL format)
├── httpdir/                    # Cloud-init configuration
│   ├── meta-data              # Instance metadata
│   └── user-data              # Cloud-init user data (creates packer user)
├── scripts/
│   └── pre-install-baremetal.sh  # Provisioning script (runs during build)
└── files/
    └── make_image_bootable.sh    # Post-deployment script (runs on target server)
```

## Building the Image

1. Navigate to this directory:
   ```bash
   cd example_build_arch
   ```

2. Initialize Packer (first time only):
   ```bash
   packer init arch-byol.pkr.hcl
   ```

3. Run Packer to build the image:
   ```bash
   packer build arch-byol.pkr.hcl
   ```

   Or with verbose logging:
   ```bash
   PACKER_LOG=1 packer build arch-byol.pkr.hcl
   ```

4. The resulting image will be in `output/arch-byol.qcow2` (approximately 1GB)

## Build Process

The build process consists of several steps:

1. **Download Base Image**: Downloads the official Arch Linux cloud image (~500MB)
2. **Generate Cloud-Init ISO**: Creates a cidata.iso with cloud-init configuration
3. **Boot VM**: Starts a QEMU VM with the base image
4. **Provision** (runs `pre-install-baremetal.sh`):
   - Updates the system packages
   - Installs required packages (mdadm, lvm2, btrfs-progs, GRUB, microcode, etc.)
   - Configures GRUB for baremetal (no quiet mode, serial console support)
   - **Configures mkinitcpio for RAID support** (critical!)
   - Removes `autodetect` hook (ensures all drivers are included)
   - Adds `mdadm_udev` hook (for software RAID support)
   - Includes NVMe, AHCI, and RAID modules explicitly
   - Regenerates initramfs with all necessary drivers
   - Enables SSH, systemd-networkd, systemd-resolved
   - Cleans up machine-id for first boot
5. **Install Boot Script**: Copies `make_image_bootable.sh` to `/root/.ovh/`
6. **Shutdown**: Gracefully shuts down the VM and compresses the image

## Critical: RAID Support

**This image is configured to support software RAID (mdadm) out of the box.**

The initramfs includes:
- `mdadm_udev` hook for RAID assembly at boot
- RAID kernel modules: `md_mod`, `raid0`, `raid1`, `raid10`, `raid456`
- NVMe drivers: `nvme`, `nvme_core`
- SATA drivers: `ahci`, `sd_mod`

**If you use RAID 0, RAID 1, or RAID 10 on your OVH server, these modules are required for boot!**

## What make_image_bootable.sh Does

This script runs **after** the image is deployed to an OVH baremetal server and **before the first boot**:

- Gets console parameters from rescue environment (for Serial-over-LAN)
- Handles mdadm configuration if RAID is detected
- Configures mkinitcpio hooks for RAID if arrays are present
- **Detects boot mode** (UEFI vs BIOS)
- **Installs GRUB** to the appropriate location:
  - UEFI: Installs to `/boot/efi` with `--no-nvram`
  - BIOS: Installs to all disks (including RAID members)
- Generates GRUB configuration
- Regenerates initramfs one final time
- Generates unique machine-id

## Partition Requirements

**IMPORTANT**: OVH BYOL requires:
- **Exactly ONE partition** for the root filesystem
- Partition must be formatted as **ext4** or **XFS**
- Do NOT create separate `/boot` and `/` partitions
- Everything (including `/boot`) must be on the single root partition

### Recommended OVH Partition Scheme

```
Disks: 2 NVMe drives
RAID: RAID 1 (recommended) or RAID 0

Single Partition:
- Filesystem: ext4
- Mount point: /
- RAID: 1 (or 0 if you prefer performance over redundancy)
- Size: Full disk
```

## Using the Image

### Upload the Image

Upload the generated `output/arch-byol.qcow2` to a web server accessible by OVH's network.

### Generate Checksum

```bash
sha512sum output/arch-byol.qcow2
```

### Deploy via OVH API

```json
POST /dedicated/server/{serviceName}/reinstall
{
  "operatingSystem": "byolinux_64",
  "customizations": {
    "hostname": "my-arch-server",
    "imageURL": "https://your-server.com/arch-byol.qcow2",
    "imageCheckSum": "YOUR_SHA512_CHECKSUM_HERE",
    "imageCheckSumType": "sha512",
    "efiBootloader": "/boot/efi/EFI/BOOT/BOOTX64.EFI",
    "configDriveUserData": "#cloud-config\nusers:\n  - name: admin\n    groups: wheel\n    sudo: ALL=(ALL) NOPASSWD:ALL\n    ssh_authorized_keys:\n      - ssh-rsa YOUR_SSH_PUBLIC_KEY_HERE"
  }
}
```

### EFI Bootloader Path

When OVH asks for the EFI bootloader path, use:
```
/boot/efi/EFI/BOOT/BOOTX64.EFI
```

### Adding Your SSH Key

Make sure to include your SSH public key in the `configDriveUserData` section, otherwise you won't be able to log in!

## Customization

### Modify Packages

Edit `scripts/pre-install-baremetal.sh` to add or remove packages:

```bash
pacman -S --noconfirm --needed \
    your-package-here \
    another-package
```

### Modify Kernel Parameters

Edit the GRUB configuration in `scripts/pre-install-baremetal.sh`:

```bash
sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="your parameters here"/' /etc/default/grub
```

### Add Custom Hooks to Initramfs

Edit the mkinitcpio HOOKS line in `scripts/pre-install-baremetal.sh`:

```bash
sed -i 's/^HOOKS=.*/HOOKS=(base systemd ... your-hook ...)/' /etc/mkinitcpio.conf
```

## Troubleshooting

### Build Issues

**Build fails during provisioning:**
- Increase memory in `arch-byol.pkr.hcl` (default is 1024MB, try 2048MB)
- Check that all required packages are available in the repositories
- Ensure stable internet connection during the build

**SSH timeout during build:**
- The VM may take 1-3 minutes to boot and start SSH
- Check if cloud-init is working by examining the build logs

### Deployment Issues

**Installation fails at "Deploying OS on disks":**
- Use **only ONE partition** for root filesystem
- Don't create separate `/boot` partition
- Ensure partition is ext4 or XFS

**Installation fails at "make_image_bootable.sh did not end properly":**
- Check the script for syntax errors
- Ensure all required packages are installed in the image
- Review make_image_bootable.sh logs via OVH console

**System stuck at "Loading initial ramdisk":**
- **Most common issue**: Missing RAID support in initramfs
- Ensure `mdadm_udev` hook is in mkinitcpio.conf
- Ensure RAID modules are included (check build logs)
- Verify initramfs was regenerated during build
- Try rebuilding the image with the latest scripts

**Cannot SSH after installation:**
- Check if you included SSH keys in `configDriveUserData`
- Use OVH KVM console to see if system booted
- Check if SSH service is running: `systemctl status sshd`
- Verify firewall isn't blocking port 22

### Getting Logs

**View boot process:**
- Use OVH's KVM/IPMI console access
- You'll see GRUB, kernel messages, and systemd output

**Check installation logs:**
- Via OVH API: `GET /dedicated/server/{serviceName}/install/status`
- Via OVH Manager: Look for "Installation logs" or "Recent tasks"

## Important Notes

- **No internet access** during `make_image_bootable.sh` execution
- All required packages must be pre-installed in the image
- The script runs in a chroot environment during OVH's deployment
- Machine-id is regenerated on first boot for uniqueness
- The `packer` user remains in the image but has no SSH keys

## Known Issues

- Missing firmware warnings during mkinitcpio are normal (GPU drivers, etc.)
- These warnings can be ignored unless you need specific hardware support
- The initramfs will still build successfully

## Related Documentation

- [OVH BYOL Documentation](https://github.com/ovh/BringYourOwnLinux)
- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Linux mkinitcpio](https://wiki.archlinux.org/title/Mkinitcpio)
- [Packer Documentation](https://www.packer.io/docs)
- [mdadm on Arch Linux](https://wiki.archlinux.org/title/RAID)
