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
: ${RELEASE:=LSDK-21.08}
: ${MC_RELEASE:=mc_release_10.37.0}
: ${DDR_SPEED:=3200}
: ${SERDES:=8_5_2}
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
: ${UBUNTU_VERSION:=focal}
: ${UBUNTU_ROOTFS_SIZE:=350M}
: ${DEBIAN_VERSION:=bullseye}
# Debian Version
# - bullseye (11)
# - bookworm (12)
: ${DEBIAN_ROOTFS_SIZE:=350M}
: ${APTPROXY:=}

if [ "x$SHALLOW" == "xtrue" ]; then
	SHALLOW_FLAG="--depth 1000"
fi

if [ "x$ATF_DEBUG" == "xtrue" ]; then
	ATF_DEBUG="DEBUG=1 LOG_LEVEL=40"
	ATF_BUILD="debug"
else
	ATF_DEBUG=""
	ATF_BUILD="release"
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
SPEED=2000_700_${DDR_SPEED}
TOOLS="tar git make 7z dd mkfs.ext4 parted mkdosfs mcopy dtc iasl mkimage e2cp truncate qemu-system-aarch64 cpio rsync bc bison flex python2 unzip pandoc meson ninja depmod"
BL2=bl2_auto

export PATH=$ROOTDIR/build/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

REPO_PREFIX=`git log -1 --pretty=format:%h || echo unknown`
echo "Repository prefix for images is $REPO_PREFIX"

case "${SERDES}" in
	0_*)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	8_9_*|8S_9_*)
		DPC=dpc-8_x_usxgmii_8_x_sgmii.dtb
		DPL=dpl-eth.8x10g.8x1g.dtb
		DEFAULT_FDT_FILE="fsl-lx2160a-half-twins.dtb"
	;;
	2_*)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	4_5_2)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	4_*)
		DPC=dpc-backplane.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	8_*|8S_*)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	10S_*)
		DPC=dpc-S1_10-S2_0-6x_usxgmii.dtb
		DPL=dpl-S1_10-S2_0-6x_eth.dtb
	;;
	13_*)
		DPC=dpc-dual-100g.dtb
		DPL=dpl-eth.dual-100g.19.dtb
	;;
	14_*)
		DPC=dpc-single-100g.dtb
		DPL=dpl-eth.single-100g.19.dtb
	;;
	17_*)
		DPC=dpc-quad-25g.dtb
		DPL=dpl-eth.quad-25g.19.dtb
	;;
	18_*)
		DPC=dpc-sd1-18.dtb
		DPL=dpl-sd1-18.dtb
	;;
	19_*)
		DPC=dpc-quad-25g.dtb
		DPL=dpl-eth.quad-25g.19.dtb
	;;
	20_*)
		DPC=dpc-dual-40g.dtb
		DPL=dpl-eth.dual-40g.19.dtb
	;;
	21_13_*)
		DPC=dpc-S1_21-S2_13-6x_25gbe-2x_sgmii.dtb
		DPL=dpl-S1_21-S2_13-6x_25gbe-2x_sgmii.dtb
	;;
	21_*)
		DPC=dpc-6x25g.dtb
		DPL=dpl-eth.6x25g.21.dtb
	;;
	LX2160ACEX6_EVB_3_3_2)
		DPC=LX2160-CEX6/evb-s1_3-s2-3-dpc.dtb
		DPL=LX2160-CEX6/evb-s1_3-s2-3-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2160a-cex6.dtb"
	;;
	LX2162A_CLEARFOG_0_0_*)
		DPC=LX2162-USOM/clearfog-s1_0-s2_0-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_0-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_3_7_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_7-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_7-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_3_9_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_9-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_9-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_3_11_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_7-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_7-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_18_9_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_9-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_9-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	*)
		echo "Please define SERDES configuration"
		exit -1
	;;
esac

# unless set above, fall back to default reference platform
: ${DEFAULT_FDT_FILE:=fsl-lx2160a-clearfog-cx.dtb}

case "${DDR_SPEED}" in
	2400|2600|2900|3200)
	;;
	*)
		echo "Please use one of allowed DDR speeds: 2400, 2600, 2900, 3200"
		exit -1
	;;
esac

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

set +e
for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		echo "If running under apt based package management you can run -"
		echo "sudo apt install build-essential git dosfstools e2fsprogs parted sudo mtools p7zip p7zip-full device-tree-compiler acpica-tools u-boot-tools e2tools qemu-system-arm libssl-dev cpio rsync bc bison flex python unzip pandoc meson ninja-build kmod"
		exit -1
	fi
done
set -e

# Check if git is configured
GIT_CONF=`git config user.name || true`
if [ "x$GIT_CONF" == "x" ]; then
	echo "git is not configured! using fake email and username ..."
	export GIT_AUTHOR_NAME="SolidRun lx2160a_build Script"
	export GIT_AUTHOR_EMAIL="support@solid-run.com"
	export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}"
	export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
fi

if [[ ! -d $ROOTDIR/build/toolchain ]]; then
	mkdir -p $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget https://releases.linaro.org/components/toolchain/binaries/7.4-2019.02/aarch64-linux-gnu/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# source code cloning
###############################################################################
QORIQ_COMPONENTS="u-boot atf ddr-phy-binary rcw restool mc-utils linux dpdk cst mdio-proxy-module"
for i in $QORIQ_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		echo "Cloning https://github.com/nxp-qoriq/$i release $RELEASE"
		cd $ROOTDIR/build
		CHECKOUT=$RELEASE
		# Release LSDK-20.12
		if [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-20.12" ]; then
			CHECKOUT=LSDK-20.12-V5.4
		fi
		# Release LSDK-20.4
		if [ "x$i" == "xu-boot" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			CHECKOUT=LSDK-20.04-update-290520
		fi
		if [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			CHECKOUT=LSDK-20.04-V5.4-update-290520
		fi
		if [ "x$i" == "xatf" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			CHECKOUT=LSDK-20.04-update-290520
		fi
		if [ "x$i" == "xrcw" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			CHECKOUT=LSDK-20.04-update-290520
		fi
		git clone $SHALLOW_FLAG https://github.com/nxp-qoriq/$i -b $CHECKOUT
		cd $i
		if [[ -d $ROOTDIR/patches/$i-$RELEASE/ ]]; then
			git am $ROOTDIR/patches/$i-$RELEASE/*.patch
		elif [[ -d $ROOTDIR/patches/$i/ ]]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
		if [[ $RELEASE == *"-update"* ]]; then
			# Check extract the LSDK name up to the '-update-...'
			SUB_RELEASE=`echo $RELEASE | cut -f-2 -d'-'`
			if [[ -d $ROOTDIR/patches/$i-$RELEASE/ ]]; then
				git am $ROOTDIR/patches/$i-$RELEASE/*.patch
			fi
		fi
	fi
done


if [[ ! -d $ROOTDIR/build/qoriq-mc-binary ]]; then
	cd $ROOTDIR/build
	git clone $SHALLOW_FLAG https://github.com/NXP/qoriq-mc-binary.git -b $MC_RELEASE
fi

###############################################################################
# building sources
###############################################################################
echo "Building restool"
cd $ROOTDIR/build/restool
CC=${CROSS_COMPILE}gcc DESTDIR=./install prefix=/usr make install

echo "Building RCW"
cd $ROOTDIR/build/rcw/lx2160acex7
mkdir -p RCW
OLDIFS=$IFS
IFS="_" arr=($SERDES)
if [ ${#arr[@]} -eq 3 ]; then
	echo "#include <configs/lx2160a_defaults.rcwi>" > RCW/template.rcw
	echo "#include <configs/lx2160a_${SPEED}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/lx2160a_SD1_${arr[0]}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/lx2160a_SD2_${arr[1]}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/lx2160a_SD3_${arr[2]}.rcwi>" >> RCW/template.rcw
fi
if [ ${#arr[@]} -eq 5 ]; then
	# extended serdes variable with soc and carrier
	echo "#include <configs/lx2160a_defaults.rcwi>" > RCW/template.rcw
	echo "#include <configs/lx2160a_${SPEED}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/${arr[0],,}_${arr[1],,}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/${arr[0],,}_${arr[1],,}_SD1_${arr[2]}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/${arr[0],,}_${arr[1],,}_SD2_${arr[3]}.rcwi>" >> RCW/template.rcw
	echo "#include <configs/${arr[0],,}_${arr[1],,}_SD3_${arr[4]}.rcwi>" >> RCW/template.rcw
fi
if [ "x$SECURE" == "xtrue" ]; then
	echo "SB_EN=1" #>> RCW/template.rcw
fi
IFS=$OLDIFS
make clean
make -j${PARALLEL}

if [ "x$SECURE" == "xtrue" ]; then
	echo "Building CST"
	cd $ROOTDIR/build/cst

	fusefilechanged=`git diff --numstat input_files/gen_fusescr/ls2088_1088/input_fuse_file`
	if [[ -z  $fusefilechanged ]]; then
	    echo "For Secure-Boot please modify \"build/cst/input_files/gen_fusescr/ls2088_1088/input_fuse_file\"!"
	    exit 1
	fi

	make
	./gen_fusescr input_files/gen_fusescr/ls2088_1088/input_fuse_file
fi

echo "Build u-boot"
cd $ROOTDIR/build/u-boot
#make distclean
if [ "x$SECURE" == "xtrue" ]; then
	make lx2160acex7_tfa_SECURE_BOOT_defconfig
else
	make lx2160acex7_tfa_defconfig
fi
if [ -n "${DEFAULT_FDT_FILE}" ]; then
	printf "CONFIG_DEFAULT_FDT_FILE=\"%s\"\n" "${DEFAULT_FDT_FILE}" >> .config
fi
make -j${PARALLEL}
make savedefconfig
export BL33=$ROOTDIR/build/u-boot/u-boot.bin

echo "Building atf"
cd $ROOTDIR/build/atf/
make PLAT=lx2160acex7 distclean
if [ "x$SECURE" == "xtrue" ]; then
	if [ ! -f "srk.pub" ] || [ ! -f "srk.pri" ]; then
		echo "Create srk.pub and srk.pri pair via ./gen_keys 4096 under $ROOTDIR/build/cst and place them under $ROOTDIR/build/atf"
		exit -1
	fi
	# Following is without COT
	# With secure boot auto mode is not supported... yet.. only flexspi_nor or sd
	# that are needed to be stated explicitly
	BL2=bl2_flexspi_nor_sec; BOOT_MODE_VAR=flexspi_nor
	make \
		-j${PARALLEL} \
		PLAT=lx2160acex7 \
		DDR_PHY_BIN_PATH=$ROOTDIR/build/ddr-phy-binary/lx2160a \
		RCW=$ROOTDIR/build/rcw/lx2160acex7/RCW/template.bin \
		TRUSTED_BOARD_BOOT=1 \
		CST_DIR=$ROOTDIR/build/cst/ \
		SECURE_BOOT=yes \
		FUSE_PROG=1 \
		FUSE_PROV_FILE=$ROOTDIR/build/cst/fuse_scr.bin \
		GENERATE_COT=0 \
		BOOT_MODE=${BOOT_MODE_VAR} \
		$ATF_DEBUG \
		all fip fip_ddr fip_fuse pbl
else
	make \
		-j${PARALLEL} \
		PLAT=lx2160acex7 \
		DDR_PHY_BIN_PATH=$ROOTDIR/build/ddr-phy-binary/lx2160a \
		RCW=$ROOTDIR/build/rcw/lx2160acex7/RCW/template.bin \
		TRUSTED_BOARD_BOOT=0 \
		SECURE_BOOT=false \
		GENERATE_COT=0 \
		BOOT_MODE=auto \
		$ATF_DEBUG \
		all fip fip_ddr pbl
       #	DDR_PHY_DEBUG=yes DDR_DEBUG=yes # DEBUG_PHY_IO=yes
fi

echo "Building mc-utils"
cd $ROOTDIR/build/mc-utils
make -C config/

echo "Building the kernel"
cd $ROOTDIR/build/linux
./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig arch/arm64/configs/lsdk.config $ROOTDIR/configs/linux/lx2k_additions.config
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
\rm -rf $ROOTDIR/images/tmp
mkdir -p $ROOTDIR/images/tmp/
mkdir -p $ROOTDIR/images/tmp/boot
make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/ INSTALL_MOD_STRIP=1 modules_install
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/Image.gz $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/freescale/fsl-lx216*.dtb $ROOTDIR/images/tmp/boot


# Build mdio-proxy kernel module
if [[ -d ${ROOTDIR}/build/mdio-proxy-module ]]; then
	cd "${ROOTDIR}/build/mdio-proxy-module"

	make -C "${ROOTDIR}/build/linux" CROSS_COMPILE="$CROSS_COMPILE" ARCH=arm64 M="$PWD" modules
	install -v -m644 -D mdio-proxy.ko "${ROOTDIR}/images/tmp/lib/modules/${KRELEASE}/kernel/extra/mdio-proxy.ko"
fi

# regenerate modules dependencies
depmod -b "${ROOTDIR}/images/tmp" -F "${ROOTDIR}/build/linux/System.map" ${KRELEASE}

function pkg_kernel() {
# package kernel individually
	rm -f "${ROOTDIR}/images/linux/linux.tar*"
	cd "${ROOTDIR}/images/tmp"; tar -c --owner=root:0 -f "${ROOTDIR}/images/linux-${REPO_PREFIX}.tar" boot/* lib/modules/*; cd "${ROOTDIR}"
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
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.2-base-arm64.tar.gz
		;;
		*)
			echo "Error: Unsupported Ubuntu Version \"\${UBUNTU_VERSION}\"! To proceed please add support to runme.sh."
			exit 1
		;;
	esac

	if [ ! -f "$ROOTDIR/build/ubuntu/$UBUNTU_VERSION.ext4" ]; then
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
	apt-get install --no-install-recommends -y apt apt-utils ethtool htop i2c-tools ifupdown iproute2 iptables iputils-ping isc-dhcp-client kmod less lm-sensors locales net-tools network-manager ntpdate openssh-server pciutils procps psmisc rng-tools sudo systemd-sysv wget
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
		fakeroot mkfs.ext4 -L rootfs -d rootfs rootfs.ext4

		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu cortex-a53 \
			-smp 1 \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,cache=unsafe,id=hd0 \
			-device virtio-blk-device,drive=hd0 \
			-device virtio-rng-device \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/boot/Image" \
			-append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 ip=dhcp rw init=/stage2.sh"
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

	ROOTFS=ubuntu-core
	cp $ROOTDIR/build/ubuntu/$UBUNTU_VERSION.ext4 $ROOTDIR/images/tmp/$ROOTFS.ext4
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

	if [ ! -f "$ROOTDIR/build/debian/$DEBIAN_VERSION.ext4" ]; then
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
			--include=apt-transport-https,busybox,ca-certificates,curl,e2fsprogs,ethtool,fdisk,haveged,i2c-tools,ifupdown,iputils-ping,isc-dhcp-client,iw,initramfs-tools,lm-sensors,localepurge,nano,net-tools,ntpdate,openssh-server,pciutils,psmisc,rfkill,sudo,systemd-sysv,tio,usbutils,wget,wpasupplicant,xz-utils \
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
		fakeroot mkfs.ext4 -L rootfs -d stage1 rootfs.ext4

		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu cortex-a53 \
			-smp 2 \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,cache=unsafe,id=hd0 \
			-device virtio-blk-device,drive=hd0 \
			-device virtio-rng-device \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/boot/Image" \
			-append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 ip=dhcp rw init=/stage2.sh"
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

	ROOTFS=debian
	cp $ROOTDIR/build/debian/$DEBIAN_VERSION.ext4 $ROOTDIR/images/tmp/$ROOTFS.ext4
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
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/Image.gz $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/fsl-lx216*.dtb $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/

# Copy over kernel image
echo "Copying kernel modules"
cd $ROOTDIR/images/tmp/
for i in `find lib`; do
	if [ -d $i ]; then
		e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:usr/$i
	fi
	if [ -f $i ]; then
		DIR=`dirname $i`
		e2cp -G 0 -O 0 -p $ROOTDIR/images/tmp/$i $ROOTDIR/images/tmp/$ROOTFS.ext4:usr/$DIR
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


truncate -s 64M $ROOTDIR/images/tmp/$ROOTFS.img
truncate -s +$ROOTFS_SIZE $ROOTDIR/images/tmp/$ROOTFS.img
parted --script $ROOTDIR/images/tmp/$ROOTFS.img mklabel msdos mkpart primary 64MiB $((64*1024*1024+ROOTFS_SIZE-1))B
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/$ROOTFS.ext4 of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1M seek=64 conv=notrunc

echo "Assembling Boot Image"
cd $ROOTDIR/
truncate -s 49M $ROOTDIR/images/tmp/boot.part
truncate -s +64M $ROOTDIR/images/tmp/boot.part
truncate -s +$ROOTFS_SIZE $ROOTDIR/images/tmp/boot.part
mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
BOOTPART_SIZE=$(stat -c "%s" $ROOTDIR/images/tmp/boot.part)

IMG=lx2160acex7_${SPEED}_${SERDES}-${REPO_PREFIX}.img
rm -rf $ROOTDIR/images/${IMG}
truncate -s 64M $ROOTDIR/images/${IMG}
truncate -s +$BOOTPART_SIZE $ROOTDIR/images/${IMG}
parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB $((64*1024*1024+BOOTPART_SIZE-1))B

\rm -rf $ROOTDIR/images/tmp/xspi_header.img
truncate -s 128K $ROOTDIR/images/tmp/xspi_header.img
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/${BL2}.pbl of=$ROOTDIR/images/tmp/xspi_header.img bs=512 conv=notrunc
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/xspi_header.img $ROOTDIR/images/tmp/boot.part:/

# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000
if [ "x$SECURE" == "xtrue" ]; then
	dd if=$ROOTDIR/build/atf/build/lx2160acex7/$ATF_BUILD/ddr_fip_sec.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
else
	dd if=$ROOTDIR/build/atf/build/lx2160acex7/$ATF_BUILD/ddr_fip.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
fi

# Env variables at 0x2800

# Secureboot headers at 0x3000

# Fuse header FIP at 0x4400
if [ "x$SECURE" == "xtrue" ]; then
	dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/fuse_fip.bin of=images/${IMG} bs=512 seek=17408 conv=notrunc
fi

# DPAA1 FMAN ucode at 0x4800

# DPAA2-MC at 0x5000
if [ "x$RELEASE" == "xLSDK-20.04" ]; then
	MC=mc_10.24.0_lx2160a.itb
	dd if=$ROOTDIR/build/qoriq-mc-binary/lx2160a/${MC} of=images/${IMG} bs=512 seek=20480 conv=notrunc
else
	if [ "x$MC_FORCE" == "x" ]; then
		MC=`ls $ROOTDIR/build/qoriq-mc-binary/lx216?a/ | grep -v sha256sum | cut -f1`
		MC=`ls $ROOTDIR/build/qoriq-mc-binary/lx216?a/${MC}`
		dd if=${MC} of=images/${IMG} bs=512 seek=20480 conv=notrunc
	else
		echo "Forcing MC firmware selection"
		MC=$MC_FORCE
		dd if=$ROOTDIR/$MC_FORCE of=images/${IMG} bs=512 seek=20480 conv=notrunc
	fi
fi

# DPAA2 DPL at 0x6800
if [[ ! $DPL =~ / ]]; then
	DPL="CEX7/$DPL"
fi
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/${DPL} of=images/${IMG} bs=512 seek=26624 conv=notrunc

# DPAA2 DPC at 0x7000
if [[ ! $DPC =~ / ]]; then
	DPC="CEX7/$DPC"
fi
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/${DPC} of=images/${IMG} bs=512 seek=28672 conv=notrunc

# Kernel at 0x8000
dd if=$ROOTDIR/build/linux/kernel-lx2160acex7.itb of=images/${IMG} bs=512 seek=32768 conv=notrunc

# Ramdisk at 0x10000
# RCW+PBI+BL2 at block 8
dd if=$ROOTDIR/images/${IMG} of=$ROOTDIR/images/lx2160acex7_xspi_${SPEED}_${SERDES}-${REPO_PREFIX}.img bs=1M count=64
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/${BL2}.pbl of=images/lx2160acex7_xspi_${SPEED}_${SERDES}-${REPO_PREFIX}.img bs=512 conv=notrunc
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/${BL2}.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc

# Copy first 64MByte from image excluding MBR to ubuntu-core.img for eMMC boot
dd if=images/${IMG} of=$ROOTDIR/images/tmp/$ROOTFS.img bs=512 seek=1 skip=1 count=131071 conv=notrunc
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.img $ROOTDIR/images/tmp/boot.part:/
dd if=$ROOTDIR/images/tmp/boot.part of=$ROOTDIR/images/${IMG} bs=1M seek=64

echo "Generated images/${IMG}"
