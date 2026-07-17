#!/bin/bash
# Convert a whole-disk-filesystem qcow2 (no partition table) into the single-
# partition image BYOL requires. Alpine cloud images ship the root filesystem
# directly on the disk (parted reports "loop"), so there is nothing for an
# in-guest partition step to remove; instead, copy the filesystem tree onto a
# fresh disk that has one MBR partition. make_image_bootable.sh installs GRUB on
# the target at deploy time, so no bootloader is needed here.
#
# Usage: wrap-single-partition.sh <image.qcow2>
set -exo pipefail

img="${1:?usage: wrap-single-partition.sh <image.qcow2>}"

# libguestfs on CI runners needs a readable kernel and the direct backend.
export LIBGUESTFS_BACKEND=direct
sudo chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tarball="$work/rootfs.tar"
new="$work/single.qcow2"

# Size the destination from the source disk plus headroom for the partition table.
bytes="$(guestfish --ro -a "$img" run : blockdev-getsize64 /dev/sda)"
dst_bytes=$(( bytes + 64 * 1024 * 1024 ))

# 1. Extract the whole-disk filesystem tree.
guestfish --ro -a "$img" <<EOF
run
mount /dev/sda /
tar-out / "$tarball"
EOF

# 2. Build a single-partition disk and unpack the tree into it.
guestfish -- disk-create "$new" qcow2 "$dst_bytes"
guestfish -a "$new" <<EOF
run
part-disk /dev/sda mbr
part-set-bootable /dev/sda 1 true
mkfs ext4 /dev/sda1
mount /dev/sda1 /
tar-in "$tarball" /
EOF

# 3. Replace the original image (compressed) with the single-partition one.
qemu-img convert -O qcow2 -c "$new" "$img"
