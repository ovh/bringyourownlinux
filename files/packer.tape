# Where should we write the GIF?
Output packer.mp4

# Set up a 1200x600 terminal with 46px font.
Set FontSize 23
Set Width 1200
Set Height 600

Type "# Everything is set for packer build"
Enter
Sleep 2s
Type "tree"
Enter
Sleep 5s
Type "PACKER_LOG=1 packer build mydistrib.json"
Enter
Sleep 70s
Type "# Listing created files"
Enter
Sleep 2s
Type "tree"
Enter
Sleep 5s
Type "file output-qemu/packer-qemu"
Enter
Sleep 3s
