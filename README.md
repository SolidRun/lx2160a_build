# SolidRun's LX2160A COM express type 7 build scripts

## Introduction
Main intention of this repository is to provide build scripts that are easy to handle than NXP's flexbuild build environment.

They are used in SolidRun quickly build images for development where those images can be SD or SPI booted or network TFTP (kernel) or used for root NFS

The sources are pinned as sub-modules and **need to downloaded explicitly** e.g. through `git submodule update --init`!

## Build with Docker
A docker image providing a consistent build environment can be used as below. Since some steps require mounting a loopback device, you need to grant permission for the container to do so when launching:

1. build container image (first time only)
   ```
   docker build -t lx2160a_build docker
   ```
2. invoke build script in working directory
   ```
   docker run --cap-add SYS_ADMIN --device /dev/loop0 --device /dev/loop-control -i -t -v "$PWD":/work lx2160a_build $(id -u) $(id -g)
   ```

## Build with host tools
Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

## Customize
By default the script will create an image bootable from SD (ready to use .img file) with DDR4 SO-DIMMs 3200Mtps, SERDES configuration 8/5/2 (SERDES1 = 8, SERDES2 = 5, SERDES = 2) and u-boot as boot loader.

Following are the environment variables that can be modified -

Selecting boot device - *BOOT=sd,xspi*

Selecting DDR4 SO-DIMM speed - *DDR_SPEED=2400,2600,2900,3200*

Selecting SERDES configuration - *SERDES=SD1_SD2_SD3*

Selecting boot loader - *BOOT_LOADER=u-boot,uefi*


### Examples:
generate sdcard image with U-Boot only - for 2600MHz ddr ram speed: *images/lx2160acex7_2000_700_2600_8_5_2_sd.img*
- BOOTLOADER_ONLY=yes ./runme.sh` **or**
- `docker run -i -t -v "$PWD":/work -e BOOTLOADER_ONLY=yes -e DDR_SPEED=2600 -e BOOT=sd -e BOOT_LOADER=u-boot lx2160a_build $(id -u) $(id -g)`

generate spi image with U-Boot only: *images/lx2160acex7_2000_700_3200_8_5_2_xspi.img*:
- `BOOT=xspi ./runme` **or**
- `docker run -i -t -v "$PWD":/work -e BOOTLOADER_ONLY=yes -e BOOT=xspi -e BOOT_LOADER=u-boot lx2160a_build $(id -u) $(id -g)`

generate *images/lx2160acex7_2000_700_3200_8_5_2_sd.img* with Ubuntu rootfs:
- `./runme.sh` **or**
- `docker run --cap-add SYS_ADMIN --device /dev/loop0 --device /dev/loop-control -i -t -v "$PWD":/work lx2160a_build $(id -u) $(id -g)`

## Deploying
For SD card bootable images, plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/lx2160acex7_2000_700_3200_8_5_2_sd.img of=/dev/sdX`
