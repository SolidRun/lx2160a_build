#!/bin/bash
set -e

###############################################################################
# General configurations
###############################################################################
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g

###############################################################################
# Misc
###############################################################################
: ${RELEASE:=ls-5.15.71-2.2.0}
: ${CPU_SPEED:=2000}
: ${DDR_SPEED:=2900}
: ${BUS_SPEED:=700}
# SoC revision
# - 1 lx2160a preview version
# - 2 (default)
: ${CPU_REVISION:=2}
# Target configuration (SoC, module, board, serdes)
: ${TARGET:=LX2160A_CEX7_HONEYCOMB_8_5_2}
# SoC Boot Source
# - auto
# - sdhc1 (microSD)
# - sdhc2 (eMMC)
# - xspi (SPI NOR Flash)
: ${BOOTSOURCE:=auto}
: ${SHALLOW:=false}
: ${SECURE:=false}
: ${ATF_DEBUG:=false}
# Distribution for rootfs
# - ubuntu
# - debian
: ${DISTRO:=ubuntu}
# Ubuntu Version
# - focal (20.04)
# - jammy (22.04)
: ${UBUNTU_VERSION:=jammy}
: ${UBUNTU_ROOTFS_SIZE:=350M}
# Debian Version
# - bullseye (11)
# - bookworm (12)
: ${DEBIAN_VERSION:=bullseye}
: ${DEBIAN_ROOTFS_SIZE:=350M}
: ${APTPROXY:=}

if [ "x$SHALLOW" == "xtrue" ]; then
	SHALLOW_FLAG="--depth 1000"
fi

# we don't have status code checks for each step - use "-e" with a trap instead
function error() {
	status=$?
	printf "ERROR: Line %i failed with status %i: %s\n" $BASH_LINENO $status "$BASH_COMMAND" >&2
	exit $status
}
trap error ERR
set -e

mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=${CPU_SPEED}_${BUS_SPEED}_${DDR_SPEED}

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

REPO_PREFIX=`git log -1 --pretty=format:%h || echo unknown`
echo "Repository prefix for images is $REPO_PREFIX"

case "${TARGET}" in
	LX2160A_CEX6_EVB_3_3_*)
		ATF_PLATFORM=lx2160acex6
		DPC=evb-s1_3-s2_0-dpc.dtb
		DPL=evb-s1_3-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-cex6-evb.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
	;;
	LX2160A_CEX7_CLEARFOG-CX_0_0_*)
		# no networking, can be used as base for new configurations
		ATF_PLATFORM=lx2160acex7
		DPC=lx2160a/LX2160A-CEX7/null-s1_0-s2_0-dpc.dtb
		DPL=lx2160a/LX2160A-CEX7/null-s1_0-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-clearfog-cx.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
	;;
	LX2160A_CEX7_CLEARFOG-CX_8_5_*|LX2160A_CEX7_CLEARFOG-CX_18_5_*)
		ATF_PLATFORM=lx2160acex7
		DPC=clearfog-cx-s1_8-s2_0-dpc.dtb
		DPL=clearfog-cx-s1_8-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-clearfog-cx.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
	;;
	LX2160A_CEX7_HONEYCOMB_8_5_*|LX2160A_CEX7_HONEYCOMB_18_5_*)
		ATF_PLATFORM=lx2160acex7
		DPC=clearfog-cx-s1_8-s2_0-dpc.dtb
		DPL=clearfog-cx-s1_8-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2160a-honeycomb.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
		RCW_BOARD=CLEARFOG-CX
	;;
	LX2162A_SOM_CLEARFOG_18_9_0)
		ATF_PLATFORM=lx2162asom
		DPC=clearfog-s1_3-s2_9-dpc.dtb
		DPL=clearfog-s1_3-s2_9-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2162a-clearfog.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
	;;
	LX2162A_SOM_CLEARFOG_18_7_0|LX2162A_SOM_CLEARFOG_18_11_0)
		ATF_PLATFORM=lx2162asom
		DPC=clearfog-s1_3-s2_7-dpc.dtb
		DPL=clearfog-s1_3-s2_7-dpl.dtb
		DEFAULT_FDT_FILE="freescale/fsl-lx2162a-clearfog.dtb"
		OPTEE_PLATFORM=ls-lx2160ardb
		UBOOT_DEFCONFIG=lx2160acex7_tfa_defconfig
	;;
	*)
		echo "Please specify a supported TARGET configuration"
		exit -1
	;;
esac

# extract components from TARGET variable if length == 6
OLDIFS=$IFS
IFS="_" arr=($TARGET)
SOC=${arr[0]}
MODULE=${arr[1]}
BOARD=${arr[2]}
SERDES=${arr[3]}_${arr[4]}_${arr[5]}
IFS=$OLDIFS

case "${DISTRO}" in
	debian|ubuntu)
		:
	;;
	*)
		echo "Please use one of the supported distros"
		exit -1
	;;
esac

echo "Checking all required tools are installed"

# Check if git is configured
GIT_CONF=`git config user.name || true`
if [ "x$GIT_CONF" == "x" ]; then
	echo "git is not configured! using fake email and username ..."
	export GIT_AUTHOR_NAME="SolidRun lx2160a_build Script"
	export GIT_AUTHOR_EMAIL="support@solid-run.com"
	export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
	export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# source code cloning
###############################################################################
QORIQ_COMPONENTS="u-boot atf ddr-phy-binary rcw restool mc-utils linux dpdk cst mdio-proxy-module optee_os qoriq-mc-binary"
for i in $QORIQ_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		echo "Cloning https://github.com/nxp-qoriq/$i release $RELEASE"
		cd $ROOTDIR/build
		CHECKOUT=$RELEASE
		COMMIT=

		# Release ls-5.15.71-2.2.0
		if [ "x$RELEASE" == "xls-5.15.71-2.2.0" ]; then
			case "$i" in
			u-boot|atf|linux|dpdk|optee_os)
				CHECKOUT=lf-5.15.71-2.2.0
			;;
			ddr-phy-binary)
				CHECKOUT=lf-5.15.5-1.0.0
			;;
			rcw|restool)
				CHECKOUT=lf-5.15.52-2.1.0
			;;
			mc-utils|cst|mdio-proxy-module)
				CHECKOUT=lf-5.15.32-2.0.0
			;;
			mc-utils)
				CHECKOUT=mc_release_10.35.0
			;;
			qoriq-mc-binary)
				CHECKOUT=mc_release_10.37.0
			;;
			esac
		fi

		if [ -z "${COMMIT}" ]; then
			git clone $SHALLOW_FLAG https://github.com/nxp-qoriq/$i -b $CHECKOUT
			cd $i
		else
			git clone https://github.com/nxp-qoriq/$i
			cd $i
			git reset --hard $COMMIT
		fi

		if [[ -d $ROOTDIR/patches/$i/ ]]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
	fi
done

###############################################################################
# building sources
###############################################################################
echo "Building restool"
cd $ROOTDIR/build/restool
CC=${CROSS_COMPILE}gcc DESTDIR=./install prefix=/usr make install

do_build_rcw() {
	local BOARD_TARGETS="lx2160acex6_rev2 lx2160acex7 lx2160acex7_rev2 lx2162asom_rev2"

	cd $ROOTDIR/build/rcw
	make BOARDS="${BOARD_TARGETS}" clean
	make BOARDS="${BOARD_TARGETS}"
	make BOARDS="${BOARD_TARGETS}" DESTDIR=${ROOTDIR}/images/tmp install
}
echo "Building RCW"
do_build_rcw

do_build_uboot() {
	cd $ROOTDIR/build/u-boot
	./scripts/kconfig/merge_config.sh configs/${UBOOT_DEFCONFIG} $ROOTDIR/configs/u-boot/lx2k_additions.config
	test -n "${DEFAULT_FDT_FILE}" && printf "CONFIG_DEFAULT_FDT_FILE=\"%s\"\n" "${DEFAULT_FDT_FILE}" >> .config || true
	make olddefconfig
	make -j${PARALLEL}
	make savedefconfig
}
echo "Build u-boot"
do_build_uboot

do_build_opteeos() {
	rm -rf $ROOTDIR/images/tmp/optee
	mkdir -p $ROOTDIR/images/tmp/optee

	# build optee devkit
	cd $ROOTDIR/build/optee_os/
	rm -rf out
	make -j${JOBS} \
		ARCH=arm \
		PLATFORM=${OPTEE_PLATFORM} \
		CROSS_COMPILE64=${CROSS_COMPILE} \
		CROSS_COMPILE32=${CROSS_COMPILE} \
		CFG_ARM64_core=y \
		ta_dev_kit

	# TODO: build external TAs

	# build optee os
	cd $ROOTDIR/build/optee_os/
	make -j${JOBS} \
		ARCH=arm \
		PLATFORM=${OPTEE_PLATFORM} \
		CROSS_COMPILE64=aarch64-linux-gnu- \
		CROSS_COMPILE32=arm-linux-gnueabihf- \
		CFG_ARM64_core=y

	cp out/arm-plat-ls/core/tee-pager_v2.bin $ROOTDIR/images/tmp/optee
}

echo "Building optee-os"
do_build_opteeos

do_build_atf() {
	local UBOOT_BINARY=$ROOTDIR/build/u-boot/u-boot.bin
	local DDR_PHY_BIN_PATH=$ROOTDIR/build/ddr-phy-binary/lx2160a
	local BUILD=release
	local DEBUG_FLAGS=
	local REV=
	if [ ${CPU_REVISION} -gt 1 ]; then
		REV=_rev${CPU_REVISION}
	fi
	if $ATF_DEBUG; then
		BUILD=debug
		DEBUG_FLAGS="DEBUG=1 LOG_LEVEL=40"
	fi
	if [ -z "${RCW_BOARD}" ]; then
		RCW_BOARD=${BOARD}
	fi
	local BOOT_MODE=
	case ${BOOTSOURCE} in
	auto)
		BOOT_MODE=auto
		RCW_BOOTSOURCE=auto
		;;
	sdhc1)
		BOOT_MODE=sd
		RCW_BOOTSOURCE=sdhc
		;;
	sdhc2)
		BOOT_MODE=emmc
		RCW_BOOTSOURCE=sdhc
		;;
	xspi)
		BOOT_MODE=flexspi_nor
		RCW_BOOTSOURCE=xspi
		;;
	*)
		echo "\"${BOOTSOURCE}\" is not a supported boot source!"
		exit 1
	esac
	local rcwimg=$ROOTDIR/images/tmp/${SOC,,}${MODULE,,}${REV}/${RCW_BOARD,,}/rcw_${CPU_SPEED}_${BUS_SPEED}_${DDR_SPEED}_${SERDES}_${RCW_BOOTSOURCE}.bin
	if [ ! -e "${rcwimg}" ]; then
		echo "cannot stat \"${rcwimg}\"!"
		echo "Please specify a supported combination of BOOTSOURCE, CPU_REVISION, CPU_SPEED, BUS_SPEED, TARGET."
		return 1
	fi

	rm -rf $ROOTDIR/images/tmp/atf
	mkdir -p $ROOTDIR/images/tmp/atf
	cd $ROOTDIR/build/atf/

	if [ "x$SECURE" == "xtrue" ]; then
		echo "Secure Boot is not supported!"
		return 1
	fi

	make realclean
	make \
		-j${PARALLEL} V=1 \
		PLAT=${ATF_PLATFORM} \
		BOOT_MODE=${BOOT_MODE} \
		RCW=${rcwimg} \
		BL32=$ROOTDIR/images/tmp/optee/tee-pager_v2.bin SPD=opteed \
		BL33=${UBOOT_BINARY} \
		DDR_PHY_BIN_PATH=$DDR_PHY_BIN_PATH \
		${DEBUG_FLAGS} \
		all fip pbl fip_ddr

	cp -v $ROOTDIR/build/atf/build/${ATF_PLATFORM}/${BUILD}/bl2_${BOOT_MODE}.pbl $ROOTDIR/images/tmp/atf/bl2.pbl
	cp -v $ROOTDIR/build/atf/build/${ATF_PLATFORM}/${BUILD}/fip.bin $ROOTDIR/images/tmp/atf/
	if $SECURE; then
		cp -v $ROOTDIR/build/atf/build/${ATF_PLATFORM}/${BUILD}/ddr_fip_sec.bin $ROOTDIR/images/tmp/atf/
		cp -v $ROOTDIR/build/atf/build/${ATF_PLATFORM}/${BUILD}/fuse_fip.bin $ROOTDIR/images/tmp/atf/
	else
		cp -v $ROOTDIR/build/atf/build/${ATF_PLATFORM}/${BUILD}/ddr_fip.bin $ROOTDIR/images/tmp/atf/ddr_fip.bin
	fi
}

echo "Building atf"
do_build_atf

echo "Building mc-utils"
cd $ROOTDIR/build/mc-utils
make -C config/

echo "Building the kernel"
cd $ROOTDIR/build/linux
./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig arch/arm64/configs/lsdk.config $ROOTDIR/configs/linux/lx2k_additions.config
make olddefconfig
make -j${PARALLEL} all #Image dtbs
KRELEASE=`make kernelrelease`

cat > kernel2160cex7.its << EOF
/dts-v1/;
/ {
	description = "arm64 kernel, ramdisk and FDT blob";
	#address-cells = <1>;
	images {
		kernel {
			description = "ARM64 Kernel";
			data = /incbin/("arch/arm64/boot/Image.gz");
			type = "kernel";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <0x80080000>;
			entry = <0x80080000>;
			hash@1 {
				algo = "crc32";
			};
		};
		initrd {
			description = "initrd for arm64";
			data = /incbin/("../../patches/ramdisk_rootfs_arm64.ext4.gz");
			type = "ramdisk";
			arch = "arm64";
			os = "linux";
			compression = "none";
			load = <0x00000000>;
			entry = <0x00000000>;
			hash@1 {
				algo = "crc32";
			};
		};
		lx2160acex7-dtb {
			description = "lx2160acex7-dtb";
			data = /incbin/("arch/arm64/boot/dts/freescale/fsl-lx2160a-clearfog-cx.dtb");
			type = "flat_dt";
			arch = "arm64";
			os = "linux";
			compression = "none";
			load = <0x90000000>;
			hash@1 {
				algo = "crc32";
			};
		};
	};
	configurations {
		lx2160acex7 {
			description = "config for lx2160acex7";
			kernel = "kernel";
			ramdisk = "initrd";
			fdt = "lx2160acex7-dtb";
                };
	};
};		
EOF

mkimage -f kernel2160cex7.its kernel-lx2160acex7.itb
\rm -rf $ROOTDIR/images/tmp/linux
mkdir -p $ROOTDIR/images/tmp/linux
mkdir -p $ROOTDIR/images/tmp/linux/boot/freescale
make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/linux/ INSTALL_MOD_STRIP=1 modules_install
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/linux/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/Image.gz $ROOTDIR/images/tmp/linux/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/freescale/fsl-lx216*.dtb $ROOTDIR/images/tmp/linux/boot/freescale/


# Build mdio-proxy kernel module
if [[ -d ${ROOTDIR}/build/mdio-proxy-module ]]; then
	cd "${ROOTDIR}/build/mdio-proxy-module"

	make -C "${ROOTDIR}/build/linux" CROSS_COMPILE="$CROSS_COMPILE" ARCH=arm64 M="$PWD" modules
	install -v -m644 -D mdio-proxy.ko "${ROOTDIR}/images/tmp/linux/lib/modules/${KRELEASE}/kernel/extra/mdio-proxy.ko"
fi

# regenerate modules dependencies
depmod -b "${ROOTDIR}/images/tmp/linux" -F "${ROOTDIR}/build/linux/System.map" ${KRELEASE}

function pkg_kernel() {
# package kernel individually
	rm -f "${ROOTDIR}/images/linux/linux.tar*"
	cd "${ROOTDIR}/images/tmp/linux"; tar -c --owner=root:0 -f "${ROOTDIR}/images/linux-${REPO_PREFIX}.tar" boot/* lib/modules/*; cd "${ROOTDIR}"
}
pkg_kernel

function pkg_kernel_headers() {
	# Build external Linux Headers package for compiling modules
	cd "${ROOTDIR}/build/linux"
	rm -rf "${ROOTDIR}/images/tmp/linux-headers"
	mkdir -p ${ROOTDIR}/images/tmp/linux-headers
	tempfile=$(mktemp)
	find . -name Makefile\* -o -name Kconfig\* -o -name \*.pl > $tempfile
	find arch/arm64/include include scripts -type f >> $tempfile
	tar -c -f - -T $tempfile | tar -C "${ROOTDIR}/images/tmp/linux-headers" -xf -
	cd "${ROOTDIR}/build/linux"
	find arch/arm64/include .config Module.symvers include scripts -type f > $tempfile
	tar -c -f - -T $tempfile | tar -C "${ROOTDIR}/images/tmp/linux-headers" -xf -
	rm -f $tempfile
	unset tempfile
	cd "${ROOTDIR}/images/tmp/linux-headers"
	tar cpf "${ROOTDIR}/images/linux-headers-${REPO_PREFIX}.tar" *
}
pkg_kernel_headers

if [[ $DISTRO == ubuntu ]]; then
	mkdir -p $ROOTDIR/build/ubuntu
	cd $ROOTDIR/build/ubuntu

	case "${UBUNTU_VERSION}" in
		focal)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.5-base-arm64.tar.gz
		;;
		jammy)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.4-base-arm64.tar.gz
		;;
		noble)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04-base-arm64.tar.gz
		;;
		*)
			echo "Error: Unsupported Ubuntu Version \"\${UBUNTU_VERSION}\"! To proceed please add support to runme.sh."
			exit 1
		;;
	esac

	# (re-)generate only if rootfs doesn't exist or runme script has changed
	if [ ! -f $UBUNTU_VERSION.ext4 ] || [[ ${ROOTDIR}/${BASH_SOURCE[0]} -nt $UBUNTU_VERSION.ext4 ]]; then
		echo Building Ubuntu rootfs

		rm -f ubuntu-base.dl
		wget -c -O ubuntu-base.dl "${UBUNTU_BASE_URL}"

		rm -rf rootfs
		mkdir rootfs
		fakeroot -- tar -C rootfs -xpf ubuntu-base.dl

cat > rootfs/stage2.sh << EOF
#!/bin/sh

# mount pseudo-filesystems
mount -vt proc proc /proc
mount -vt sysfs sysfs /sys

# mount tmpfs for apt caches
mount -t tmpfs tmpfs /var/lib/apt/
mount -t tmpfs tmpfs /var/cache/apt/

# configure dns
cat /proc/net/pnp > /etc/resolv.conf

# configure hostname
echo "localhost" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts

# configure apt proxy
test -n "$APTPROXY" && printf 'Acquire::http { Proxy "%s"; }\n' $APTPROXY | tee -a /etc/apt/apt.conf.d/proxy || true

apt-get update
env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C \
	apt-get install --no-install-recommends -y apt apt-utils ethtool fdisk htop i2c-tools ifupdown iproute2 iptables iputils-ping isc-dhcp-client kmod less lm-sensors locales net-tools network-manager ntpdate openssh-server pciutils procps psmisc rng-tools sudo systemd-sysv tee-supplicant wget
apt-get clean

# set root password
echo "root\nroot" | passwd

# populate fstab
printf "/dev/root / ext4 defaults 0 1\\n" > /etc/fstab

# enable watchdog service
sed -i "s;[# ]*RuntimeWatchdogSec=.*\$;RuntimeWatchdogSec=30;g" /etc/systemd/system.conf

# wipe machine-id (regenerates during first boot)
echo uninitialized > /etc/machine-id

# remove apt proxy
rm -f /etc/apt/apt.conf.d/proxy

# delete self
rm -f /stage2.sh

# flush disk
sync

# power-off
reboot -f
EOF
		chmod +x rootfs/stage2.sh

		rm -f rootfs.ext4
		truncate -s $UBUNTU_ROOTFS_SIZE rootfs.ext4

		# create filesystem from first stage
		fakeroot mkfs.ext4 -L rootfs -d rootfs rootfs.ext4

		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu max,pauth-impdef=on,sve=on \
			-smp 4 \
			-device virtio-rng-device \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,id=hd0,discard=unmap \
			-device virtio-blk-device,drive=hd0 \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/linux/boot/Image" \
			-append "earlycon console=ttyAMA0 root=/dev/vda rootfstype=ext4 ip=dhcp rw init=/stage2.sh"
		:

		# fix errors
		s=0
		e2fsck -fy rootfs.ext4 || s=$?
		if [ $s -ge 4 ]; then
			echo "Error: Couldn't repair generated rootfs."
			exit 1
		fi

		mv rootfs.ext4 $UBUNTU_VERSION.ext4
	fi

	# export final rootfs for next steps
	ROOTFS=ubuntu-core
	cp --sparse=always $UBUNTU_VERSION.ext4 $ROOTDIR/images/tmp/$ROOTFS.ext4
fi

if [[ $DISTRO == debian ]]; then
	mkdir -p $ROOTDIR/build/debian
	cd $ROOTDIR/build/debian

	case "${DEBIAN_VERSION}" in
		bullseye)
			EXCLUDE=--exclude=gcc-9-base
		;;
		bookworm)
			EXCLUDE=
		;;
		*)
			echo "Error: Unsupported Debian Version \"\${DEBIAN_VERSION}\"! To proceed please add support to runme.sh."
			exit 1
		;;
	esac

	# (re-)generate only if rootfs doesn't exist or runme script has changed
	if [ ! -f $DEBIAN_VERSION.ext4 ] || [[ ${ROOTDIR}/${BASH_SOURCE[0]} -nt $DEBIAN_VERSION.ext4 ]]; then
		echo Building Debian rootfs

		# use apt mirror, if available
		URL="https://deb.debian.org/debian"
		if [ ! -z "$APTPROXY" ]; then
			MIRROR="$APTPROXY/debian"
		else
			MIRROR="$URL"
		fi

		# bootstrap a first-stage rootfs
		rm -rf stage1
		fakeroot debootstrap --variant=minbase \
			--arch=arm64 --components=main,contrib,non-free \
			--foreign \
			--include=apt-transport-https,busybox,ca-certificates,curl,e2fsprogs,ethtool,fdisk,haveged,i2c-tools,ifupdown,iputils-ping,isc-dhcp-client,iw,initramfs-tools,lm-sensors,localepurge,nano,net-tools,ntpdate,openssh-server,pciutils,psmisc,rfkill,sudo,systemd-sysv,tee-supplicant,tio,usbutils,wget,wpasupplicant,xz-utils \
			${EXCLUDE} \
			$DEBIAN_VERSION \
			stage1 \
			$MIRROR

		# prepare init-script for second stage inside VM
cat > stage1/stage2.sh << EOF
#!/bin/sh

# run second-stage bootstrap
/debootstrap/debootstrap --second-stage

# mount pseudo-filesystems
mount -vt proc proc /proc
mount -vt sysfs sysfs /sys

# configure dns
cat /proc/net/pnp > /etc/resolv.conf

# configure default locale
echo en_GB.UTF-8 UTF-8 >> /etc/locale.gen
echo "locales locales/default_environment_locale string en_GB.UTF-8" | debconf-set-selections
dpkg-reconfigure -f noninteractive locales

# clean all other locales to save space
sed -i "s;#\?\(USE_DPKG\)$;#\1;g" /etc/locale.nopurge
sed -i "s;#\?\(DONTBOTHERNEWLOCALE\)$;\1;g" /etc/locale.nopurge
sed -i "s;#\?\(NEEDSCONFIGFIRST\);en\nen_GB\nen_GB.UTF-8;g" /etc/locale.nopurge
localepurge
sed -i "s;#\?\(USE_DPKG\)$;\1;g" /etc/locale.nopurge
dpkg-reconfigure -f noninteractive localepurge

# clean documentation to save more space
find /usr/share/doc/ -type f ! -name changelog -delete

# set root password
echo "root\nroot" | passwd

# populate fstab
printf "/dev/root / ext4 defaults 0 1\\n" > /etc/fstab

# enable watchdog service
sed -i "s;[# ]*RuntimeWatchdogSec=.*\$;RuntimeWatchdogSec=30;g" /etc/systemd/system.conf

# wipe machine-id (regenerates during first boot)
echo uninitialized > /etc/machine-id

# remove apt proxy from sources.list
sed -i "s;$MIRROR;$URL;g" /etc/apt/sources.list

# clean caches
apt-get clean
rm -rf /var/lib/apt/lists/*

# delete self
rm -f /stage2.sh

# flush disk
sync

# power-off
reboot -f
EOF
		chmod +x stage1/stage2.sh

		stagesize=$(LANG=C du -B 1048576 -s stage1 | cut -f1)

		rm -f rootfs.ext4
		truncate -s $DEBIAN_ROOTFS_SIZE rootfs.ext4
		truncate -s +${stagesize}M rootfs.ext4

		# create filesystem from first stage
		fakeroot mkfs.ext4 -L rootfs -d stage1 rootfs.ext4

		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu max,pauth-impdef=on,sve=on \
			-smp 4 \
			-device virtio-rng-device \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,id=hd0,discard=unmap \
			-device virtio-blk-device,drive=hd0 \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/linux/boot/Image" \
			-append "earlycon console=ttyAMA0 root=/dev/vda rootfstype=ext4 ip=dhcp rw init=/stage2.sh"
		:


		# fix errors
		s=0
		e2fsck -fy rootfs.ext4 || s=$?
		if [ $s -ge 4 ]; then
			echo "Error: Couldn't repair generated rootfs."
			exit 1
		fi

		# shrink to desired size
		resize2fs rootfs.ext4 $DEBIAN_ROOTFS_SIZE
		truncate -s $DEBIAN_ROOTFS_SIZE rootfs.ext4

		mv rootfs.ext4 $DEBIAN_VERSION.ext4
	fi

	# export final rootfs for next steps
	ROOTFS=debian
	cp --sparse=always $DEBIAN_VERSION.ext4 $ROOTDIR/images/tmp/$ROOTFS.ext4
fi

if [ -z "$ROOTFS" ] || [ ! -f "$ROOTDIR/images/tmp/$ROOTFS.ext4" ]; then
	echo "Internal Error: No rootfs was generated!"
	exit 1
fi
ROOTFS_SIZE=$(stat -c "%s" $ROOTDIR/images/tmp/$ROOTFS.ext4)


echo "Building DPDK"
cd $ROOTDIR/build/dpdk
export CROSS=$CROSS_COMPILE
export RTE_SDK=$ROOTDIR/build/dpdk
export DESTDIR=$ROOTDIR/build/dpdk/install
export RTE_TARGET=arm64-dpaa-linuxapp-gcc
meson arm64-dpaa-build -Dexamples=all --cross-file config/arm/arm64_dpaa_linux_gcc
ninja -C arm64-dpaa-build


###############################################################################
# assembling images
###############################################################################
echo "Assembling kernel and rootfs image"
cd $ROOTDIR
mkdir -p $ROOTDIR/images/tmp/extlinux/
cat > $ROOTDIR/images/tmp/extlinux/extlinux.conf << EOF
  timeout 30
  default linux
  menu title linux-lx2160a boot options
  label primary
    menu label primary kernel
    linux /boot/Image.gz
    fdtdir /boot/
    APPEND console=ttyAMA0,115200 earlycon=pl011,mmio32,0x21c0000 default_hugepagesz=1024m hugepagesz=1024m hugepages=2 pci=pcie_bus_perf root=PARTUUID=30303030-01 rw rootwait
EOF

e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:extlinux
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/extlinux/extlinux.conf $ROOTDIR/images/tmp/$ROOTFS.ext4:extlinux/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:boot
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/linux/boot/Image.gz $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/freescale
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/linux/boot/freescale/fsl-lx216*.dtb $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/freescale/

# Copy over kernel image
echo "Copying kernel modules"
cd $ROOTDIR/images/tmp/linux/
for i in `find lib`; do
	if [ -d $i ]; then
		e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:usr/$i
	fi
	if [ -f $i ]; then
		DIR=`dirname $i`
		e2cp -G 0 -O 0 -p $ROOTDIR/images/tmp/linux/$i $ROOTDIR/images/tmp/$ROOTFS.ext4:usr/$DIR
	fi
done
cd -

# install restool
echo "Install restool"
cd $ROOTDIR/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-append-dpl $ROOTDIR/images/tmp/$ROOTFS.ext4:/usr/bin/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-main $ROOTDIR/images/tmp/$ROOTFS.ext4:/usr/bin/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/restool $ROOTDIR/images/tmp/$ROOTFS.ext4:/usr/bin/
e2ln images/tmp/$ROOTFS.ext4:/usr/bin/ls-main /usr/bin/ls-addmux
e2ln images/tmp/$ROOTFS.ext4:/usr/bin/ls-main /usr/bin/ls-addni
e2ln images/tmp/$ROOTFS.ext4:/usr/bin/ls-main /usr/bin/ls-addsw
e2ln images/tmp/$ROOTFS.ext4:/usr/bin/ls-main /usr/bin/ls-listmac
e2ln images/tmp/$ROOTFS.ext4:/usr/bin/ls-main /usr/bin/ls-listni

# collect generated images
declare -a IMAGES

echo "Assembling rootfs Image"
cd $ROOTDIR/
truncate -s 64M $ROOTDIR/images/tmp/$ROOTFS.img
truncate -s +$ROOTFS_SIZE $ROOTDIR/images/tmp/$ROOTFS.img
ROOTFS_IMG_SIZE=$(stat -c "%s" $ROOTDIR/images/tmp/$ROOTFS.img)
parted --script $ROOTDIR/images/tmp/$ROOTFS.img mklabel msdos mkpart primary 64MiB $((64*1024*1024+ROOTFS_SIZE-1))B
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/$ROOTFS.ext4 of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1M seek=64 conv=notrunc
IMAGES+=("images/tmp/$ROOTFS.img")

# add default prefix for short DPL/DPC variables
if [[ ! $DPL =~ / ]]; then
	DPL="${SOC,,}/${SOC^^}-${MODULE^^}/$DPL"
fi
if [[ ! $DPC =~ / ]]; then
	DPC="${SOC,,}/${SOC^^}-${MODULE^^}/$DPC"
fi

# select MC firmware file
MC=`ls $ROOTDIR/build/qoriq-mc-binary/lx216?a/ | grep -v sha256sum | cut -f1`
MC=`ls $ROOTDIR/build/qoriq-mc-binary/lx216?a/${MC}`

# shared function for placing artifacts in boot image
do_populate_bootimg() {
	local IMG="$1"
	local BOOTSOURCE="$2"

	if [[ ${BOOTSOURCE} == sdhc* ]]; then
		# RCW+PBI+BL2 at 0x1000 (block 0x8)
		dd if=$ROOTDIR/images/tmp/atf/bl2.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc
	elif [ "${BOOTSOURCE}" = "xspi" ]; then
		# RCW+PBI+BL2 at 0x0000000 (block 0x0000)
		dd if=$ROOTDIR/images/tmp/atf/bl2.pbl of=images/${IMG} bs=512 seek=0 conv=notrunc
	fi

	# FIP (BL31+BL32+BL33) at 0x0100000 (block 0x800)
	dd if=$ROOTDIR/images/tmp/atf/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

	# DDR PHY FIP at 0x0800000 (block 0x4000)
	dd if=$ROOTDIR/images/tmp/atf/ddr_fip.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc

	# Fuse header FIP at 0x0880000 (block 0x4400)
	if [ "x$SECURE" == "xtrue" ]; then
		dd if=$ROOTDIR/images/tmp/atf/fuse_fip.bin of=images/${IMG} bs=512 seek=17408 conv=notrunc
	fi

	# DPAA2-MC at 0x0a00000 (block 0x5000)
	dd if=${MC} of=images/${IMG} bs=512 seek=20480 conv=notrunc

	# DPAA2 DPL at 0x0d00000 (block 0x6800)
	dd if=$ROOTDIR/build/mc-utils/config/${DPL} of=images/${IMG} bs=512 seek=26624 conv=notrunc

	# DPAA2 DPC at 0x0e00000 (block 0x7000)
	dd if=$ROOTDIR/build/mc-utils/config/${DPC} of=images/${IMG} bs=512 seek=28672 conv=notrunc

	# DTB at 0x0f00000 (block 0x7800)

	# Kernel at 0x1000000 (block 0x8000)
	dd if=$ROOTDIR/build/linux/kernel-lx2160acex7.itb of=images/${IMG} bs=512 seek=32768 conv=notrunc
}

# generate SPI boot image
if ([ "${BOOTSOURCE}" = "auto" ] || [ "${BOOTSOURCE}" = "xspi" ]); then
	echo "Assembling XSPI Boot Image"
	cd $ROOTDIR/

	XSPI_IMG=${SOC,,}_rev${CPU_REVISION}_${MODULE,,}_${BOARD,,}_xspi_${CPU_SPEED}_${BUS_SPEED}_${DDR_SPEED}_${SERDES}-${REPO_PREFIX}.img
	rm -rf $ROOTDIR/images/${XSPI_IMG}
	truncate -s 64M $ROOTDIR/images/${XSPI_IMG}

	do_populate_bootimg "${XSPI_IMG}" xspi

	IMAGES+=("images/${XSPI_IMG}")
fi

# generate SD boot image
if ([ "${BOOTSOURCE}" = "auto" ] || [[ ${BOOTSOURCE} == sdhc* ]]); then
	echo "Assembling SDHC Boot Image"
	cd $ROOTDIR/

	# generate partition 1 for boot image
	truncate -s 49M $ROOTDIR/images/tmp/boot.part
	truncate -s +$ROOTFS_IMG_SIZE $ROOTDIR/images/tmp/boot.part
	truncate -s +64M $ROOTDIR/images/tmp/boot.part
	mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
	BOOTPART_SIZE=$(stat -c "%s" $ROOTDIR/images/tmp/boot.part)

	# generate boot image
	IMG=${SOC,,}_rev${CPU_REVISION}_${MODULE,,}_${BOARD,,}_${CPU_SPEED}_${BUS_SPEED}_${DDR_SPEED}_${SERDES}-${REPO_PREFIX}.img
	rm -rf $ROOTDIR/images/${IMG}
	truncate -s 64M $ROOTDIR/images/${IMG}
	truncate -s +$BOOTPART_SIZE $ROOTDIR/images/${IMG}
	parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB $((64*1024*1024+BOOTPART_SIZE-1))B

	if [ "${BOOTSOURCE}" = "auto" ]; then
		e2cp -G 0 -O 0 $ROOTDIR/images/${XSPI_IMG} $ROOTDIR/images/tmp/boot.part:/xspi.img
	fi

	do_populate_bootimg "${IMG}" sdhc

	# Copy first 64MByte from image excluding MBR to rootfs image, making it bootable
	dd if=images/${IMG} of=$ROOTDIR/images/tmp/$ROOTFS.img bs=512 seek=1 skip=1 count=131071 conv=notrunc

	# Copy rootfs image as a file into boot image for eMMC installation
	e2cp -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.img $ROOTDIR/images/tmp/boot.part:/
	dd if=$ROOTDIR/images/tmp/boot.part of=$ROOTDIR/images/${IMG} bs=1M seek=64

	IMAGES+=("images/${IMG}")
fi

for IMG in ${IMAGES[@]}; do
	echo "Generated ${IMG}"
done
