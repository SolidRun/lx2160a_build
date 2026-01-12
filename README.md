# SolidRun's LX2160A build scripts

Main intention of this repository is to produce a reference system for LX2160A product evaluation.
Automatic binary releases are available on [our website](https://images.solid-run.com/LX2k/lx2160a_build) for download.

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

### Download Build Scripts

The full build process is managed by the [runme.sh](runme.sh) script in this very repository.
Clone the current branch to a build directory of choice:

    git clone -b develop-ls-5.15.71-2.2.0 https://github.com/SolidRun/lx2160a_build.git

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

Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory:

- `images/tmp/ubuntu-core.img`: for SD-Card, Bootloader and OS on SD-Card
- `images/lx2160a_rev2_cex7_clearfog-cx_xspi_2000_700_2900_8_5_2-<HASH>.img`: for SPI Flash, Bootloader only
- `images/lx2160a_rev2_cex7_clearfog-cx_2000_700_2900_8_5_2-<HASH>.img`: for SD-Card, supports installation of Bootloader & OS to eMMC, supports installation of Bootloader to SPI Flash

### Configure Build Options

By default the script will create an image bootable from SD (ready to use .img file) with DDR4 SO-DIMMs 2900Mtps, SERDES configuration `8_5_2` (SERDES1 = 8, SERDES2 = 5, SERDES = 2) suitable for Clearfog CX and Honeycomb.

Build options can be customised by passing environment variables to the runme script / docker/
For example:

- `./runme.sh TARGET=LX2162A_SOM_CLEARFOG_18_9_0 CPU_REVISION=1` **or**
- `docker run --rm -i -t -v "$PWD":/work -e TARGET=LX2162A_SOM_CLEARFOG_18_9_0 -e CPU_REVISION=2 -e BUS_SPEED=650 lx2160a_build -u $(id -u) -g $(id -g)`

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
  - `2666`
  - `2600`
  - `2400`
- `BUS_SPEED`: Platform clock in MHz
  - `650`
  - `700`: only for LX2160A binned 2GHz and higher (default)
  - `750`: only for LX2160A binned 2.2GHz
- `CPU_REVISION`: select soc revision
  - `1`: LX2160A preview version
  - `2`: LX2160A production version (default)
- `TARGET`: Select Board and Serdes Protocols (for list of valid choices see `runme.sh`)
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

The easiest way to start development is reuse of an existing configuration `TARGET` setting and make changes where required.
It comes however at the cost of merging future upstream changes not having customer boards in mind.

The intended method is as follows:

1. Define a specific configuration for the `TARGET` setting. The variable is a combination of multiple parameters: `<SOC>_<MODULE>_<BOARD>_<SERDES-1>_<SERDES-2>_<SERDES-3>`

   For example a ficticious board called "Waffle" using LX2160A CEX-7 with Serdes 1 Protocol 1, Serdes 2 Protocol 13 and Serdes 3 Protocol 3 should be named: `LX2160A_CEX7_WAFFLE_1_13_3`

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

   Within the `case "${SOC^^}${MODULE^^}_${BOARD^^}_${SERDES}" in` block, add a new entry:

   ```
   	LX2160A_CEX7_WAFFLE_1_13_3)
   		ATF_PLATFORM=lx2160acex7
   		DPC=LX2160A-CEX7/waffle-s1_1-s2_13-dpc.dtb
   		DPL=LX2160A-CEX7/waffle-s1_1-s2_13-dpl.dtb
   		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-waffle.dtb"
   		OPTEE_PLATFORM=ls-lx2160ardb
   		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
   	;;
   ```

5. Configure U-Boot device-tree filename:

   `DEFAULT_FDT_FILE` makes the default of u-boot `fdtfile` variable. Note however that U-Boot generates different names in most cases.
   Currently (see `build/u-boot/board/solidrun/lx2160a/eth_lx2160acex7.c:fsl_board_late_init`) LX2160 defaults to "fsl-lx2160a-clearfog-cx.dtb", and LX2162 defaults to "fsl-lx2162a-som-\<SD1>-\<SD2>.dtb".
   Therefore it is recommended to add a match for selected serdes protocol in this function and force the correct filename.

6. Create RCW Configuration Files:

   Based on the configuration name the build system expects reset configuration file at `build/rcw/<MODULE>_rev<CPU_REVISION>/<BOARD>/rcw_<CPU_SPEED>_<BUS_SPEED>_<DDR_SPEED>_<SERDES-1>_<SERDES-2>_<SERDES-3>_<BOOTSOURCE>.rcw`.
   For the Waffle example: `build/rcw/lx2160acex7_rev2/clearfog-cx/rcw_<CPU_SPEED>_<BUS_SPEED>_<DDR_SPEED>_1_13_3_auto.rcw`.

   It may reference shared include files, e.g.:

   - `build/rcw/lx2160asi/lx2160a.rcwi`: LX2160A / LX2162A SoC Defaults
   - `build/rcw/lx2160acex7/include/pll_<CPU_SPEED>_<BUS_SPEED>_xxxx.rcwi`: CPU & Bus Frequency Selection
   - `build/rcw/lx2160acex7/include/pll_xxxx_xxx_<DDR_SPEED>.rcwi`: DDR Frequency Selection
   - `build/rcw/lx2160acex7/include/SD1_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7/include/SD2_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7/include/SD3_<PROTOCOL>.rcwi`:  Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7/include/common.rcwi`: SolidRun defaults for LX2160A CEX-7
   - `build/rcw/lx2160acex7/include/common_pbi.rcwi`: SolidRun defaults for LX2160A CEX-7
   - `build/rcw/lx2160acex7/clearfog-cx/sd1_8_eq.rcwi`: SolidRun SerDes Equalization settings for Clearfog-CX

   Safe reference points in case uart stays silent are protocols `0` (`SRDS_PRTCL_S1=0`, `SRDS_PRTCL_S2=0`, `SRDS_PRTCL_S3=0`).

## Deploying

The build generates several images serving different purposes:

- `*_emmc_*_*-*.img`:

  Bootloader + RootFS for installation to eMMC data partition.

- `*_multi_*_*-*.img`:

  SD-bootable installation image for deploying to either eMMC or SPI Flash.
  Embeds `emmc.img` (Bootloader + RootFS) and `xspi.img` (Bootloader only).

- `*_sd_*_*-*.img`:

  Bootloader + RootFS for installation to microSD.

- `*_xspi_*_*-*.img`:

  Bootloader only for installationto SPI Flash.

### SD Boot

For SD boot, plug in a micro SD into your machine and program `*_sd_*_*-*.img` to it using the commands below (sdX should be replaced to the actual device thatsdcard was recognised as):

`sudo dd if=images/lx2160acex7_rev2_clearfog-cx_2000_700_2900_8_5_2-<HASH>.img of=/dev/sdX`

Finally change boot DIP switch on COM to off/on/on/on from numbers 1 to 4 (dip number 5 is not used. Notice the marking 'ON' on the DIP switch).

### SPI Boot

For SPI boot, boot `*_multi_*_*-*.img` from microSD - then load the `xspi.img` to system memory and flash it using the `sf probe` and `sf update` commands:

```
load mmc 0:1 $kernel_addr_r xspi.img
sf probe
sf update $kernel_addr_r 0 0x4000000
```

Finally change boot DIP switch on COM to off/off/off/off from numbers 1 to 4 (dip number 5 is not used. Notice the marking 'ON' on the DIP switch).

### eMMC Boot

For eMMC boot (supported only thru LX2160A silicon rev 2 which is LX2160A COM Express type 7 rev 1.5 and newer), boot `*_multi_*_*-*.img` from microSD - then load the `emmc.img` to system memory and flash it using `mmc` command:

```
load mmc 0:1 $kernel_addr_r emmc.img
setexpr filesize 0x$filesize + 0x1ff
setexpr filesize 0x$filesize / 0x200
mmc dev 1
mmc write $kernel_addr_r 0 0xd2000
```

Finally change boot DIP switch on COM to off/on/on/off from numbers 1 to 4 (dip number 5 is not used. Notice the marking 'ON' on the DIP switch).

## Post Install

After booting Ubuntu you must resize the boot partition; for instance if booted under eMMC then login as root/root; then fdisk /dev/mmcblk1; delete first partition and then recreate it starting from 131072 (64MByte) to the end of the volume.
Do not remove the signaute since it indicates for the kernel which partition ID to use.

After resizing the partition; resize the ext4 boot volume by running 'resize2fs /dev/mmcblk1p1'

Afterwards run update the RTC and update the repository -

`dhclient -i eth0; ntpdate pool.ntp.org; apt update`

If using a GPU then install the linux-firmware package that contains GPU firmwares -

`apt install linux-firmware`

## Known Issues

### SFP Ports with Retimer can't link up

The 2x 25Gbps ports on LX2162A Clearfog, and the QSFP on Clearfog-CX can't detect link.
RX direction is not currently functional, no known workaround.
