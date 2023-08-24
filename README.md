# SolidRun's LX2160A COM express type 7 build scripts

## Introduction
Main intention of this repository is to provide build scripts that are easy to handle than NXP's flexbuild build environment.

They are used in SolidRun to quickly build images for development where those images can be SD or SPI booted or network TFTP (kernel) or used for root NFS

The sources are pulled from NXP's codeaurora repository and patched after being clone using the patches in the patches/ directory

The build script builds the u-boot, atf, rcw and linux components, integrate it with Ubuntu rootfs bootstrapped with multistrap. Buildroot is also built aside for future use.


## Build with Docker
A docker image providing a consistent build environment can be used as below:

1. build container image (first time only)
   ```
   docker build -t lx2160a_build docker
   # optional with an apt proxy, e.g. apt-cacher-ng
   # docker build --build-arg APTPROXY=http://127.0.0.1:3142 -t lx2160a_build docker
   ```
2. invoke build script in working directory
   ```
   docker run --rm -i -t -v "$PWD":/work lx2160a_build -u $(id -u) -g $(id -g)
   ```

### rootless Podman

Due to the way podman performs user-id mapping, the root user inside the container (uid=0, gid=0) will be mapped to the user running podman (e.g. 1000:100).
Therefore in order for the build directory to be owned by current user, `-u 0 -g 0` have to be passed to *docker run*.

## Build with host tools
Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

We enhanced the NXP PBI scripting tools to accomodate auto detection of boot device, due to that the boot images are now unified for SD, eMMC and SPI.

## Customize

### Configure Build Options

By default the script will create an image bootable from SD (ready to use .img file) with DDR4 SO-DIMMs 3200Mtps, SERDES configuration `8_5_2` (SERDES1 = 8, SERDES2 = 5, SERDES = 2) suitable for Clearfog CX and Honeycomb.

Build options can be customised by passing environment variables to the runme script / docker/
For example:

- `./runme.sh SERDES=LX2162A_CLEARFOG_18_9_0` **or**
- `docker run --rm -i -t -v "$PWD":/work -e SERDES=LX2162A_CLEARFOG_18_9_0 lx2160a_build -u $(id -u) -g $(id -g)`

generates *images/lx2160acex7_2000_700_3200_8_5_2.img* which is an image ready to be deployed on micro SD card and *images/lx2160acex7_xspi_2000_700_3200_8_5_2.img* which is an image ready to be deployed on the COM SPI flash.

#### Available Options:

- `RELEASE`: select nxp bsp version
  - `LSDK-21.08` (default)
  - `LSDK-20.12`
  - `LSDK-20.04`
- `MC_RELEASE`: force specific version of Network Coprocessor Firmware
  - `mc_release_10.37.0`: full release supporting serdes protocol change USXGMII/CAUI (default)
  - `mc_lx2160a_10.36.100.itb`: prerelease supporting serdes protocol change USXGMII/CAUI
  - `mc_lx2160a_10.36.0.itb`
  - `mc_lx2160a_10.32.0.itb`: full release supporting serdes protocol change SGMII/USXGMII
  - `mc_10.28.100_lx2160a.itb`: prerelease supporting serdes protocol change SGMII/USXGMII
- `DDR_SPEED`: DDR speed in MHz increments
  - `3200`
  - `2900`
  - `2600`
  - `2400`
- `SERDES`: Select Board and Serdes Protocols (for list of valid choices see `runme.sh`)
- `SHALLOW`: enable shallow git clone to save space and bandwidth
  - `false` (default)
  - `true`
- `SECURE`: enable secure-boot
  - `false` (default)
  - `true`
- `ATF_DEBUG`: enable debug build of atf
  - `false` (default)
  - `true`
- `DISTRO`: Distribution for rootfs
  - `debian`
  - `ubuntu` (default)
- `UBUNTU_VERSION`: Ubuntu Version
  - focal (20.04, default)
  - jammy (22.04)
- `UBUNTU_ROOTFS_SIZE`: rootfs / partition size
  - `350M` (default)
  - arbitrary sizes supported in unit `M`, 350M recommended minimum
- `DEBIAN_VERSION`: Debian Version
  - bullseye (11, default)
  - bookworm (12)
- `DEBIAN_ROOTFS_SIZE`: rootfs / partition size
  - `350M` (default)
  - arbitrary sizes supported in unit `M`, 350M recommended minimum
- `APTPROXY`: specify url to a local apt cache, e.g. apt-cacher-ng

## Deploying
For SD card bootable images, plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/lx2160acex7_2000_700_3200_8_5_2_sd.img of=/dev/sdX`

For SPI boot, boot thru SD card and then load the _xspi_ images to system memory and flash it using the `sf probe` and `sf update` commands. An example below loads the image through TFTP prototocl, flashes and then verifies the image -

`sf probe; setenv ipaddr 192.168.15.223; setenv serverip 192.168.15.3; tftp 0xa0000000 lx2160acex7_xspi_2000_700_2600_8_5_2_xspi.img;sf update 0xa0000000 0 $filesize; sf read 0xa4000000 0 $filesize; cmp.b 0xa0000000 0xa4000000 $filesize`

And then set boot DIP switch on COM to off/off/off/off from numbers 1 to 4 (dip number 5 is not used. Notice the marking 'ON' on the DIP switch)

For eMMC boot (supported only thru LX2160A silicon rev 2 which is LX2160A COM Express type 7 rev 1.5 and newer) -

`load mmc 0:1 0xa4000000 ubuntu-core.img`

`mmc dev 1`

`mmc write 0xa4000000 0 0xd2000`

And then set boot DIP switch on COM to off/on/on/off from numbers 1 to 4 (dip number 5 is not used, notice the marking 'ON' on the DIP switch)

After booting Ubuntu you must resize the boot partition; for instance if booted under eMMC then login as root/root; then fdisk /dev/mmcblk1; delete first partition and then recreate it starting from 131072 (64MByte) to the end of the volume.
Do not remove the signaute since it indicates for the kernel which partition ID to use.

After resizing the partition; resize the ext4 boot volume by running 'resize2fs /dev/mmcblk1p1'

Afterwards run update the RTC and update the repository -

`dhclient -i eth0; ntpdate pool.ntp.org; apt update`

If using a GPU then install the linux-firmware package that contains GPU firmwares -

`apt install linux-firmware`
