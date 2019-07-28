# SolidRun's LX2160A COM express type 7 build scripts

## Introduction
Main intention of this repository is to provide build scripts that are easy to handle than NXP's flexbuild build environment.

They are used in SolidRun quickly build images for development where those images can be SD or SPI booted or network TFTP (kernel) or used for root NFS

The sources are pulled from NXP's codeaurora repository and patched after being clone using the patches in the patches/ directory

## Build
Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

By default the script will create an image bootable from SD (ready to use .img file) with DDR4 SO-DIMMs 3200Mtps, SERDES configuration 8/5/2 (SERDES1 = 8, SERDES2 = 5, SERDES = 2) and u-boot as boot loader.

Following are the environment variables that can be modified -

Selecting boot device - *BOOT=sd,xspi*

Selecting DDR4 SO-DIMM speed - *DDR_SPEED=2400,2600,2900,3200*

Selecting SERDES configuration - *SERDES=SD1_SD2_SD3*

Selecting boot loader - *BOOT_LOADER=u-boot,uefi*


Examples - 
`./runme.sh` will generate *images/lx2160acex7_2000_700_3200_8_5_2_sd.img*
`BOOT=xspi ./runme` will generate *images/lx2160acex7_2000_700_3200_8_5_2_xspi.img*

## Deploying
For SD card bootable images, plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/lx2160acex7_2000_700_3200_8_5_2_sd.img of=/dev/sdX`
