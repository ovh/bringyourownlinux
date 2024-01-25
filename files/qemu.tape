# Where should we write the GIF?
Output qemu.mp4

# Set up a 1200x600 terminal with 46px font.
Set FontSize 23
Set Width 1200
Set Height 600

Type "# We'll download debian12 lastest qcow2"
Enter
Sleep 2s
Type "wget -nv -nc https://cdimage.debian.org/cdimage/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
Enter
Sleep 5s
Type "md5sum debian-12-generic-amd64.qcow2"
Enter
Sleep 5s
Type "# we are now creating a root password"
Enter
Sleep 2s
Type "virt-customize -a debian-12-generic-amd64.qcow2 --root-password password:password"
Enter
Sleep 10s
Type "md5sum debian-12-generic-amd64.qcow2"
Enter
Sleep 5s
Type "# the file has changed, now run the image and start customization"
Enter
Sleep 2s
Type "qemu-system-x86_64 -m 512 -nographic -hda debian-12-generic-amd64.qcow2 -device vmxnet3,netdev=eno1 -netdev user,id=eno1" 
Enter
Sleep 60s
Type "root"
Enter
Sleep 2s
Type "password"
Enter
Sleep 5s
Type "echo 'hello' > .ovh"
Enter
Sleep 5s
Type "poweroff"
Enter
Sleep 10s
Type "# Checking if the file still here"
Enter
Sleep 2s
Type "qemu-system-x86_64 -m 512 -nographic -hda debian-12-generic-amd64.qcow2 -device vmxnet3,netdev=eno1 -netdev user,id=eno1" 
Enter
Sleep 60s
Type "root"
Enter
Sleep 2s
Type "password"
Enter
Sleep 5s
Type "cat .ovh"
Enter
Sleep 3s
Type "poweroff"
Enter
Sleep 10s
