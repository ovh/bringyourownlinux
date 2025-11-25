# Bring Your Own Linux

- [What is it?](#what)
- [Requirements](#reqs)
- [How to make a BYOL compatible image](#howto)
  - [From a QCOW2 file](#qcow2)
    - [With Qemu](#qemu)
    - [With Packer](#packer)
  - [Other methods](#othermethods)
- [How to use it?](#useit)
  - [Via api.ovh.com](#api)
  - [Via the OVH manager](#manager)
- [How does it work?](#workit)
  - [Partitioning the disks](#partdisk)
  - [Create config-drive](#configdrive)
  - [Download and burn the customer's image](#burncustomer)
  - [`make_image_bootable.sh`](#mib)
- [Related links](#links)

<a name="what"></a>

## What is it?

Bring Your Own Linux is somewhat of an extension of the [Bring Your Own Image](https://help.ovhcloud.com/csm/en-dedicated-servers-bringyourownimage?id=kb_article_view&sysparm_article=KB0043281) feature.
It enables you to install any Linux of you choice with additional features, like:

- Custom partitioning [using the OVHcloud API](https://help.ovhcloud.com/csm/en-dedicated-servers-api-partitioning?id=kb_article_view&sysparm_article=KB0043882), [software RAID](https://help.ovhcloud.com/csm/en-dedicated-servers-raid-soft?id=kb_article_view&sysparm_article=KB0043935), LVM, ZFS, etc.
- Custom `Cloud-init` meta-data

<a name="reqs"></a>

## Requirements

- Baremetal Server
- Working qcow2 image
  - Only one partition
  - The partition must be formatted with either `ext4` or `XFS`
  - An executable `/root/.ovh/make_image_bootable.sh` script inside the partition

<a name="howto"></a>

## How to make a BYOL-compatible image: two examples

<a name="qcow2"></a>

### From an already packaged QCOW2 file

You can use an already packaged Linux image made by your favorite distro:

- [Debian](https://cdimage.debian.org/cdimage/cloud/)
- [Ubuntu](http://cloud-images.ubuntu.com/)
- [Fedora](https://alt.fedoraproject.org/en/cloud/)
- whatever Linux you want

> Be aware that some Linux distributions have virtualization-oriented kernels within their QCOW2 images.
> When trying to boot these kernels on baremetal servers, there might be some problems.

<a name="qemu"></a>

#### Handmade image with QEMU

![qemu-cli-video](files/qemu.mp4)

_The following procedure was executed on a Debian 11 bare metal server as the `root` user_

```bash
# qemu-system will be used to connect to the virtual machine
# libguestfs-tools will allow you to change the root password before booting
apt install -y qemu-system libguestfs-tools
wget https://cdimage.debian.org/cdimage/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
virt-customize -a debian-12-generic-amd64.qcow2 --root-password password:password
qemu-system-x86_64 -m 512 -nographic -hdb debian-12-generic-amd64.qcow2 -device vmxnet3,netdev=eno1 -netdev user,id=eno1
# you are now on the login prompt of the image
# and you can begin customization
```

> Be careful as you might not have enough space left on the disk to add too much stuff.

```bash
root@localhost:~# df -h
Filesystem      Size  Used Avail Use% Mounted on
udev            210M     0  210M   0% /dev
tmpfs            46M  408K   46M   1% /run
/dev/sda1       1.9G  997M  744M  58% /
tmpfs           229M     0  229M   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
/dev/sda15      124M   12M  113M  10% /boot/efi
tmpfs            46M     0   46M   0% /run/user/0
```

As seen in the video, every modification done while in `qemu` will be saved.
You can add scripts, files, packages, services.

<a name="packer"></a>

#### Example with Packer (using QEMU)

_All the following process is done on a Debian 11 baremetal server as `root` user_

> Contrary to the previous method, you can add all you want in this one
> as `packer` will automatically expend the disk.

![packer-cli-video](files/packer.mp4)

1. A `mydistrib.json` file is required to run packer

    See example in this [file](example_build/mycustomdebian12.json)

2. An `httpdir` directory containing:
    - an empty `meta-data` file
      or can be filled like this [one](example_build/httpdir/meta-data)
    - a `user-data` file that can either be a script, as follow:

        ```bash
        #!/bin/bash
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get -y update
        apt-get -y install linux-image-amd64
        apt-get -y autoremove
        apt-get clean
        shutdown -Hr now
        ```

      or a `cloud-init` script like this [one](example_build/httpdir/user-data)

3. Install `packer`, `qemu-system-x86`, `genisoimage`, and `qemu-utils`

    ```bash
        apt install --no-install-recommends packer qemu-system-x86 qemu-utils genisoimage
    ```

4. Run packer

    ```bash
        PACKER_LOG=1 packer build mydistrib.json
    ```

5. The resulting image is in `<output_directory>/<vm_name>`

<a name="othermethods"></a>

### Other possible methods

Although we will not provide detailed procedures for these, the following methods could also be used (not an exhaustive list):

- From an ISO installation in a VM (possibly via Packer)
- Using tools such as `debootstrap`

<a name="useit"></a>

## How to use it?

<a name="api"></a>

### Via [OVHcloud API](https://eu.api.ovh.com/console/?section=%2Fdedicated%2Fserver&branch=v1#post-/dedicated/server/-serviceName-/reinstall)

You can use a home-made script, and use a payload like this one:

`POST /dedicated/server/{serviceName}/reinstall`

```json
{
  "operatingSystem": "byolinux_64",
  "customizations": {
    "hostname": "myHostname",
    "imageURL": "https://github.com/myself/myImagesFactory/releases/download/0.1/myCustomImage.qcow2",
    "imageCheckSum": "6a65719e6a7f276a4b8685d3ace0920d56acef7d4bbbf9427fe188db7b19c23be7fc182f7a9b29e394167717731f4cd7cab410a36e60e6c6451954f3b795a15c",
    "httpHeaders": {
      "Authorization": "Basic dGhlb3dsc2FyZW5vdDp3aGF0dGhleXNlZW1z="
    },
    "imageCheckSumType": "sha512",
    "configDriveUserData": "#!/bin/bash\necho \"Hi, sounds like BYOLinux as ostemplate is a success!\" >/etc/motd"
  }
}
```

The key elements here are:

- `operatingSystem`: which is `boylinux_64`
- `customizations`: which holds all information to pass to the installer
- `customizations/httpHeaders`: which can be configured, if necessary the call to retrieve the customer image.
    In this example, we set a basic authentication
- the other items in `customizations` seem quite self-explanatory

<a name="manager"></a>

### Via the [OVHcloud Control Panel](https://www.ovh.com/manager/#/dedicated/configuration)


Log in to the [OVHcloud Control Panel](https://www.ovh.com/auth/?action=gotomanager&from=https://www.ovh.co.uk/&ovhSubsidiary=GB) and go to the `Bare Metal Cloud`{.action} section, then select your server under `Dedicated servers`{.action}.

In the `General information`{.action} tab, click the `...`{.action} button next to "System (OS)" then click `Install`{.action} (or `Reinstall`{.action}).

![BringYourOwnLinux Control Panel 01](files/byolinux-controlpanel01.png){.thumbnail}

In the window that appears, select `Custom` in the menu, then `Bring Your Own Linux - byolinux`, and click `Next`{.action}.

![BringYourOwnLinux Control Panel 03](files/byolinux-controlpanel03.png){.thumbnail}

You will be redirected to the configuration page. Make sure your image URL is in the correct format. Complete the rest of the required fields on this page. Once you have confirmed that the information is correct, click `Confirm`{.action}.

You can find more details on the options in the [deployment options](#options) section below.

For more information and examples about Cloud-Init's ConfigDrive, please read the official documentation on [this page](https://cloudinit.readthedocs.io/en/22.1_a/topics/examples.html).

![BringYourOwnLinux Control Panel 04](files/byolinux-controlpanel04.png){.thumbnail}

<a name="workit"></a>

## How does it work?

1. Partitioning the disks
2. Creating a `config-drive` partition
3. Download and burn the customer's image
4. Set boot order
5. Run `make_image_bootable.sh`
6. Reboot

<a name="partdisk"></a>

### Partitioning the disks

> For an in-depth presentation about partitioning at OVHcloud, see the official [documentation](https://help.ovhcloud.com/csm/fr-dedicated-servers-api-partitioning?id=kb_article_view&sysparm_article=KB0043888)

With the provided partition scheme, the disks will be partitioned
and formatted with the selected filesystem.
All partitions are mounted on their respecting mount points in `/tmp/a/`.

```bash
/tmp/a/home
/tmp/a/boot
/tmp/a/var
```

<a name="configdrive"></a>

### Create `config-drive`

Provided `cloud-init`'s meta-data files will be copied in a small vfat partition at the end of the disk.

<a name="burncustomer"></a>

### Download and burn the customer's image

The provided image is downloaded in ram/disk[?], and mounted with `qemu-nbd` in `/dev/shm/image`.
All the content of the image is then `rsynced` to the disks

<a name="mib"></a>

### `make_image_bootable.sh`

`make_image_bootable.sh` have to be located in `/root/.ovh/` and be executable.

The script is executed once, right after the image is deployed on partitioned disk, and right before the first reboot into the new installation.

The script can be used, for instance, to generate an adhoc initramfs, embedding drivers dedicated to the system the image will boot on.

> There is no internet access at this moment, so if you try to install something not
already in the image, it will fail.

See [`make_image_bootable.sh`](example_build/files/make_image_bootable.sh) example file.

<a name="links"></a>

## Related links

* [Contribute](https://github.com/ovh/BringYourOwnLinux/blob/master/CONTRIBUTING.md)
* [Report bugs](https://github.com/ovh/BringYourOwnLinux/issues)
