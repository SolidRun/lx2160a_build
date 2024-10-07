# SolidRun's LX2160A COM express type 7 build scripts

## Introduction
Main intention of this repository is to provide build scripts that are easy to handle than NXP's flexbuild build environment.

They are used in SolidRun to quickly build images for development where those images can be SD or SPI booted or network TFTP (kernel) or used for root NFS

The sources are pulled from NXP's GitHub repository and patched after being clone using the patches in the patches/ directory

The build script builds the u-boot, atf, rcw and linux components, integrate it with Ubuntu rootfs bootstrapped with multistrap. Buildroot is also built aside for future use.

Automatic binary releases are available on [our website](https://images.solid-run.com/LX2k/lx2160a_build) for download (latest versions are in subfolders named by build date).

## Get Started

For basic usage refer to our various quick-start guides:

- [LX2160A HoneyComb / ClearFog CX Quick Start Guide](https://solidrun.atlassian.net/wiki/spaces/developer/pages/197494288/HoneyComb+LX2+ClearFog+CX+LX2+Quick+Start+Guide)
- [LX2162A ClearFog Quick Start Guide](https://solidrun.atlassian.net/wiki/spaces/developer/pages/199131187/ClearFog+LX2162A+Quick+Start+Guide)

This document provides development resources only.

## Compiling External Kernel Modules

Kernel modules can be built using the "linux-headers" package for a specific image.
It is available in the same place as binary images on [our website](https://images.solid-run.com/LX2k/lx2160a_build).

### Preparations for Cross-Build on x86_64 Host

Modules should be compiled in the same environment as the original images:
x86_64 host, Debian 10, `apt-get install crossbuild-essential-arm64`.

### Preparations for Native Build on LX2160

The kernel headers package includes binary programs built for x86_64.
For a native build QEMU user-mode emulation packages must be installed and configured,
to allow transparent execution of these programs:

    apt-get update
    apt-get install qemu-user-binfmt

Install amd64 library dependencies:

       apt-get install libc6-amd64-cross
       ln -sv /lib /lib64
       ln -sv /usr/x86_64-linux-gnu/lib/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2
       ln -sv /usr/x86_64-linux-gnu/lib /usr/lib/x86_64-linux-gnu

Install native toolchain:

    apt-get install build-essential ca-certificates

### Compiling the Module

After configuration of the build host according to the previous steps,
a ficticious module may be compiled for binary images `20240328-ec11295/lx2160acex7_2000_700_*_*-ec11295.img.xz` using the steps below:

```
wget https://images.solid-run.com/LX2k/lx2160a_build/20240328-ec11295/linux-headers-ec11295.tar.xz
mkdir linux-headers-ec11295
tar -C linux-headers-ec11295 -xf linux-headers-ec11295.tar.xz

cd kernel-mod-src

make -C ../linux-headers-ec11295/ CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 M="$PWD" modules
ls *.ko
```

In case the module requires access to kernel private headers not included in -headers package,
it must be built as part of a full image. See [runme.sh](https://github.com/SolidRun/ti_am64x_build/blob/main/runme.sh) function `build_atemsys` for an example.


## Build Full Image from Source with Docker

### Build Full Image from Source with Docker

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

#### rootless Podman

Due to the way podman performs user-id mapping, the root user inside the container (uid=0, gid=0) will be mapped to the user running podman (e.g. 1000:100).
Therefore in order for the build directory to be owned by current user, `-u 0 -g 0` have to be passed to *docker run*.

### Build Full Image from Source with host tools

Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

We enhanced the NXP PBI scripting tools to accomodate auto detection of boot device, due to that the boot images are now unified for SD, eMMC and SPI.

### Configure Build Options

By default the script will create an image bootable from SD (ready to use .img file) with DDR4 SO-DIMMs 3200Mtps, SERDES configuration `8_5_2` (SERDES1 = 8, SERDES2 = 5, SERDES = 2) suitable for Clearfog CX and Honeycomb.

Build options can be customised by passing environment variables to the runme script / docker/
For example:

- `./runme.sh SERDES=LX2162A_CLEARFOG_18_9_0` **or**
- `docker run --rm -i -t -v "$PWD":/work -e SERDES=LX2162A_CLEARFOG_18_9_0 lx2160a_build -u $(id -u) -g $(id -g)`

generates *images/lx2160acex7_2000_700_3200_8_5_2.img* which is an image ready to be deployed on micro SD card and *images/lx2160acex7_xspi_2000_700_3200_8_5_2.img* which is an image ready to be deployed on the COM SPI flash.

#### Available Options:

- `RELEASE`: select nxp bsp version
  - `ls-5.15.71-2.2.0` (default)
- `BOOTSOURCE`: select soc boot source
  - `auto` (default)
  - `sdhc1` micro-SD
  - `xspi` SPI NOR Flash
- `CPU_SPEED`: DDR speed in MHz increments
  - `2000` (default)
  - `2200`
- `DDR_SPEED`: DDR speed in MHz increments
  - `3200` only for LX2160A binned 2.2GHz
  - `2900` only for LX2162A, and LX2160A binned 2GHz and higher (default)
  - `2600`
  - `2400`
- `BUS_SPEED`: Platform clock in MHz
  - `700`: only for LX2160A binned 2GHz and higher (default)
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

## Customize

### Adding a new Configuration

The easiest way to start development is reuse of an existing configuration `SERDES` setting and make changes where required.
It comes however at the cost of merging future upstream changes not having customer boards in mind.

The intended method is as follows:

1. Define a specific configuration for the `SERDES` setting. The variable is a combination of multiple parameters: `<SOC>_<BOARD>_<SERDES-1>_<SERDES-2>_<SERDES-3>`

   For example a ficticious board called "Waffle" using LX2160A CEX-7 with Serdes 1 Protocol 1, Serdes 2 Protocol 13 and Serdes 3 Protocol 3 should be named: `LX2160A_WAFFLE_1_13_3`

2. Create configuration files DPL & DPC for the network coprocessor:

   - `build/mc-utils/config/lx2160a/LX2160A-CEX7/waffle-s1_1-s2_13-dpc.dts`
   - `build/mc-utils/config/lx2160a/LX2160A-CEX7/waffle-s1_1-s2_13-dpl.dts`

   Safe starting points are configurations that disable all network interfaces:

   - `build/mc-utils/config/lx2160a/LX2160A-CEX7/null-s1_0-s2_0-dpc.dts`
   - `build/mc-utils/config/lx2160a/LX2160A-CEX7/null-s1_0-s2_0-dpl.dts`

   DPC must be edited by hand. DPL can be auto-generated with `restool` command after booting linux and manually instantiating dpmac and optionally dpni objects.

3. Create Linux device-tree file: `build/linux/arch/arm64/boot/dts/freescale/fsl-lx2160a-waffle.dts`

   And add it to the `build/linux/arch/arm64/boot/dts/freescale/Makefile`.

4. Add configuration to `runme.sh`:

   Within the `case "${SERDES}" in` block, add a new entry:

   ```
   	LX2160A_WAFFLE_1_13_3)
   		DPC=LX2160A-CEX7/waffle-s1_1-s2_13-dpc.dtb
   		DPL=LX2160A-CEX7/waffle-s1_1-s2_13-dpl.dtb
   		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-waffle.dtb"
   	;;
   ```

5. Configure U-Boot device-tree filename:

   `DEFAULT_FDT_FILE` makes the default of u-boot `fdtfile` variable. Note however that U-Boot generates different names in most cases.
   Currently (see `build/u-boot/board/solidrun/lx2160a/eth_lx2160acex7.c:fsl_board_late_init`) LX2160 defaults to "fsl-lx2160a-clearfog-cx.dtb", and LX2162 defaults to "fsl-lx2162a-som-\<SD1>-\<SD2>.dtb".
   Therefore it is recommended to add a match for selected serdes protocol in this function and force the correct filename.

6. Create RCW Configuration Files:

   Based on the configuration name the build system expects reset configuration file at `build/rcw/lx2160acex7_rev2/clearfog-cx/rcw_<CPU_SPEED>_700_<DDR_SPEED>_<SERDES>.rcw`.
   For the Waffle example: `build/rcw/lx2160acex7_rev2/clearfog-cx/rcw_<CPU_SPEED>_700_<DDR_SPEED>_1_13_3.rcw`.

   It may reference using shared include files, e.g.:

   - `build/rcw/lx2160acex7_rev2/include/common.rcwi`: SolidRun defaults for LX2160A CEX-7 / LX2162A SoM
   - `build/rcw/lx2160acex7_rev2/include/pll_<CPU_SPEED>_700_xxxx.rcwi`: CPU Frequency Selection
   - `build/rcw/lx2160acex7_rev2/include/pll_xxxx_700_<DDR_SPEED>.rcwi`: DDR Frequency Selection
   - `build/rcw/lx2160acex7_rev2/include/SD1_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7_rev2/include/SD2_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7_rev2/include/SD3_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed

   Safe reference points in case uart stays silent are protocols `0` (`SRDS_PRTCL_S1=0`, `SRDS_PRTCL_S2=0`, `SRDS_PRTCL_S3=0`).

## Deploying

### SD Boot

For SD card bootable images, plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/lx2160acex7_2000_700_3200_8_5_2_sd.img of=/dev/sdX`

And then set boot DIP switch on COM to off/on/on/on from numbers 1 to 4 (dip number 5 is not used, notice the marking 'ON' on the DIP switch)

### SPI Boot

For SPI boot, boot thru SD card and then load the `xspi.img` to system memory and flash it using the `sf probe` and `sf update` commands.

```
load mmc 0:1 $kernel_addr_r xspi.img
sf probe
sf update $kernel_addr_r 0 0x4000000
```

And then set boot DIP switch on COM to off/off/off/off from numbers 1 to 4 (dip number 5 is not used. Notice the marking 'ON' on the DIP switch)

### eMMC Boot

For eMMC boot (supported only thru LX2160A silicon rev 2 which is LX2160A COM Express type 7 rev 1.5 and newer) -

Either full image including MBR and rootfs:

```
load mmc 0:1 $kernel_addr_r ubuntu-core.img
mmc dev 1
mmc write $kernel_addr_r 0 0xd2000
```

OR bootcode only (first 64MB excluding MBR):

```
load mmc 0:1 $kernel_addr_r ubuntu-core.img
setexpr mbroffset ${kernel_addr_r} + 0x200
mmc dev 1
mmc write 0x${mbroffset} 1 0x1FFFF
```

And then set boot DIP switch on COM to off/on/on/off from numbers 1 to 4 (dip number 5 is not used, notice the marking 'ON' on the DIP switch)

## Post Install

After booting Ubuntu you must resize the boot partition; for instance if booted under eMMC then login as root/root; then fdisk /dev/mmcblk1; delete first partition and then recreate it starting from 131072 (64MByte) to the end of the volume.
Do not remove the signaute since it indicates for the kernel which partition ID to use.

After resizing the partition; resize the ext4 boot volume by running 'resize2fs /dev/mmcblk1p1'

Afterwards run update the RTC and update the repository -

`dhclient -i eth0; ntpdate pool.ntp.org; apt update`

If using a GPU then install the linux-firmware package that contains GPU firmwares -

`apt install linux-firmware`
