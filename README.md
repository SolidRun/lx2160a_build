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

### Adding a new Configuration

The easiest way to start development is reuse of an existing configuration `SERDES` setting and make changes where required.
It comes however at the cost of merging future upstream changes not having customer boards in mind.

The intended method is as follows:

1. Define a specific configuration for the `SERDES` setting. The variable is a combination of multiple parameters: `<SOC>_<BOARD>_<SERDES-1>_<SERDES-2>_<SERDES-3>`

   For example a ficticious board called "Waffle" using LX2160A CEX-7 with Serdes 1 Protocol 1, Serdes 2 Protocol 13 and Serdes 3 Protocol 3 should be named: `LX2160A_WAFFLE_1_13_3`

2. Create configuration files DPL & DPC for the network coprocessor:

   - `build/mc-utils/config/lx2160a/CEX7/waffle-s1_1-s2_13-dpc.dts`
   - `build/mc-utils/config/lx2160a/CEX7/waffle-s1_1-s2_13-dpl.dts`

   Safe starting points are configurations that disable all network interfaces:

   - `build/mc-utils/config/lx2160a/LX2162-USOM/clearfog-s1_0-s2_0-dpc.dts`
   - `build/mc-utils/config/lx2160a/LX2162-USOM/clearfog-s1_0-s2_0-dpl.dts`

   DPC must be edited by hand. DPL can be auto-generated with `restool` command after booting linux and manually instantiating dpmac and optionally dpni objects.

3. Create Linux device-tree file: `build/linux/arch/arm64/boot/dts/freescale/fsl-lx2160a-waffle.dts`

   And add it to the `build/linux/arch/arm64/boot/dts/freescale/Makefile`.

4. Add configuration to `runme.sh`:

   Within the `case "${SERDES}" in` block, add a new entry:

   ```
   	LX2160A_WAFFLE_1_13_3)
   		DPC=CEX7/waffle-s1_1-s2_13-dpc.dtb
   		DPL=CEX7/waffle-s1_1-s2_13-dpl.dtb
   		DEFAULT_FDT_FILE="fsl-lx2160a-waffle.dtb"
   	;;
   ```

5. Configure U-Boot device-tree filename:

   `DEFAULT_FDT_FILE` makes the default of u-boot `fdtfile` variable. Note however that U-Boot generates different names in most cases.
   Currently (see `build/u-boot/board/solidrun/lx2160a/eth_lx2160acex7.c:fsl_board_late_init`) LX2160 defaults to "fsl-lx2160a-clearfog-cx.dtb", and LX2162 defaults to "fsl-lx2162a-som-\<SD1>-\<SD2>.dtb".
   Therefore it is recommended to add a match for selected serdes protocol in this function and force the correct filename.

6. Create RCW Configuration Files:

   Based on the configuration name the build system generates reset configuration for the SoC from the following files (lower-case names):

   - `build/rcw/lx2160acex7/configs/lx2160a_defaults.rcwi`: SolidRun defaults for LX2160A CEX-7 / LX2162A SoM
   - `build/rcw/lx2160acex7/configs/lx2160a_<SPEED>.rcwi`: DDR Frequency Selection
   - `build/rcw/lx2160acex7/configs/<SOC>_<BOARD>.rcwi`: Board-specific configuration, e.g. pinmux
   - `build/rcw/lx2160acex7/configs/<SOC>_<BOARD>_SD1_<Serdes-1 Protocol>.rcwi`: Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7/configs/<SOC>_<BOARD>_SD2_<Serdes-2 Protocol>.rcwi`: Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed
   - `build/rcw/lx2160acex7/configs/<SOC>_<BOARD>_SD3_<Serdes-3 Protocol>.rcwi`: Serdes-Protocol-specific configuration, e.g. serdes clocks and pci-e speed

   For the Waffle example:

   - `build/rcw/lx2160acex7/configs/lx2160a_defaults.rcwi`
   - `build/rcw/lx2160acex7/configs/lx2160a_<SPEED>.rcwi`
   - `build/rcw/lx2160acex7/configs/lx2160a_waffle.rcwi`
   - `build/rcw/lx2160acex7/configs/lx2160a_waffle_SD1_1.rcwi`
   - `build/rcw/lx2160acex7/configs/lx2160a_waffle_SD2_13.rcwi`
   - `build/rcw/lx2160acex7/configs/lx2160a_waffle_SD3_3.rcwi`

   For examples see `build/rcw/lx2160acex7/configs/lx2162a_clearfog*.rcwi` as these include comments with explanations.

   Safe reference points in case uart stays silent are protocols `0` (`SRDS_PRTCL_S1=0`, `SRDS_PRTCL_S2=0`, `SRDS_PRTCL_S3=0`).


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
