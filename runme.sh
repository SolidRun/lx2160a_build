#!/bin/bash -x
set -e

# BOOT=sd,xspi
# BOOT_LOADER=u-boot,uefi
# DDR_SPEED=2400,2600,2900,3200
# SERDES=8_5_2, 13_5_2, 20_5_2

###############################################################################
# General configurations
###############################################################################
RELEASE=LSDK-19.09
BUILDROOT_VERSION=2019.05.2
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds

#UEFI_RELEASE=DEBUG
#BOOT=xspi
#BOOT_LOADER=uefi
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g

function usage {
	echo "Usage: $0 [-d|--debug]
		  [-v|--verbose]
		  [-c|--cleanup]
		  [-b|--boot sd|xspi]
		  [-s|--serdes 8x10G|2x100G|2x40G]
		  [--uefi-debug]
		  [--bootloader-only]
		  [--bootloader u-boot|uefi]
		  [--ddr-speed 2400|2600|2900|3200] " 1>&2;
}

function args {
	local POSITIONAL=()
	if [ $# -eq 0 ]; then
		echo "Missing option(s), aborting..."
		usage
		exit -1
	fi
	while [ $# -gt 0 ]; do
		echo "Parsed option => $1"
		case "$1" in
			-v|--verbose)
				VERBOSE=1
				shift
				;;
			-d|--debug)
				DEBUG=1
				shift
				;;
			--bootloader-only)
				BOOTLOADER_ONLY="YES"
				shift
				;;
			--bootloader)
				if [ "$2" == "u-boot" ]; then
					BOOT_LOADER="u-boot"
				elif [ "$2" == "uefi" ]; then
					BOOT_LOADER="uefi"
				else
					echo "Incorrect bootloader selected"
				  usage
					exit -1
				fi
				echo "Parsed value  => $2"
				shift 2
				;;
			--uefi-debug)
				UEFI_RELEASE="DEBUG"
				if [ $MAKE_CLEAN ]; then
					echo "Options '--uefi-debug' and '--cleanup' are mutually exclusive, aborting..."
					usage
					exit 1
				fi
				shift
				;;
			-c|--cleanup)
				MAKE_CLEAN="YES"
				if [[ $UEFI_RELEASE && $UEFI_RELEASE==DEBUG ]]; then
					echo "Options '--cleanup' and '--uefi-debug' are mutually exclusive, aborting..."
					usage
					exit 1
				fi
				shift
				;;
			-b|--boot)
				if [ "$2" == "sd" ]; then
					BOOT="sd"
				elif [ "$2" == "xspi" ]; then
					BOOT="xspi"
				else
					echo "Incorrect boot medium selected"
				  usage
					exit -1
				fi
				echo "Parsed value  => $2"
				shift 2
				;;
			--serdes)
				#SERDES=8_5_2 is 8x10g
				#SERDES=13_5_2 is dual 100g
				#SERDES=20_5_2 is dual 40g
				if [ "$2" == "8x10G" ]; then
					SERDES="8_5_2"
				elif [ "$2" == "2x100G" ]; then
					SERDES="13_5_2"
				elif [ "$2" == "2x40G" ]; then
					SERDES="20_5_2"
				else
					echo "Incorrect SerDes configuration selected"
				  usage
					exit -1
				fi
				echo "Parsed value  => $2"
				shift 2
				;;
			--ddr-speed)
				if [ "$2" == "2400" ]; then
					DDR_SPEED=$2
				elif [ "$2" == "2600" ]; then
					DDR_SPEED=$2
				elif [ "$2" == "2900" ]; then
					DDR_SPEED=$2
				elif [ "$2" == "3200" ]; then
					DDR_SPEED=$2
				else
					echo "Incorrect DDR SPEED"
				  usage
					exit -1
				fi
				echo "Parsed value  => $2"
				shift 2
				;;
			*)
				echo "Unknown option(s): $1"
				usage
				exit -1
		esac
	done
}

args "$@"
set -- "${POSITIONAL[@]}" # restore positional parameters

###############################################################################
# Misc
###############################################################################

if [ -z "$BOOT" ]; then
	BOOT=sd
fi

if [ -z "$BOOT_LOADER" ]; then
	BOOT_LOADER=u-boot
fi

if [ -z "$DDR_SPEED" ]; then
	DDR_SPEED=3200
fi

if [ -z "$SERDES" ]; then
	SERDES=8_5_2
fi

if [ -z "$UEFI_RELEASE" ]; then
	UEFI_RELEASE=RELEASE
fi

mkdir -p images/tmp

SPEED=2000_700_${DDR_SPEED}

# sudo apt install p7zip-full uuid-dev build-essential git dosfstools 
# e2fsprogs parted sudo mtools device-tree-compiler acpica-tools 
# u-boot-tools e2tools multistrap qemu-user-static libssl-dev cpio 
# rsync bc bison flex"

if [ $BOOTLOADER_ONLY ]; then
	TOOLS="wget tar git make dd envsubst"
	echo "Bootloader only compilation -> selected tools: $TOOLS"
else
	TOOLS="wget tar git make 7z unsquashfs dd envsubst vim mkfs.ext4 sudo parted"
	TOOLS="$TOOLS mkdosfs mcopy dtc iasl mkimage e2cp truncate multistrap qemu-aarch64-static"
	echo "Full image compilation -> selected tools: $TOOLS"
fi

HOST_ARCH=`arch`

if [ "$HOST_ARCH" == "x86_64" ]; then
	export CROSS_COMPILE="$ROOTDIR"/build/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
fi

export ARCH=arm64

if [ -z "$SERDES" ]; then
	echo "Please define SERDES configuration"
	exit -1
fi
if [ "${SERDES:0:3}" == "13_" ]; then
	DPC=dpc-dual-100g.dtb
	DPL=dpl-eth.dual-100g.19.dtb
fi
if [ "${SERDES:0:2}" == "8_" ]; then
	DPC=dpc-8_x_usxgmii.dtb
	DPL=dpl-eth.8x10g.19.dtb
fi
if [ "${SERDES:0:2}" == "4_" ]; then
	DPC=dpc-8_x_usxgmii.dtb
	DPL=dpl-eth.8x10g.19.dtb
fi
if [ "${SERDES:0:3}" == "20_" ]; then
	DPC=dpc-dual-40g.dtb
	DPL=dpl-eth.dual-40g.19.dtb
fi

echo "Checking all required tools are installed"
set +e
for i in $TOOLS; do
	TOOL_PATH=`which $i`
	echo -n "Is tool '$i' installed ? "
	if [ -z "$TOOL_PATH" ]; then
		echo "No"
		exit -1
	else
		echo "Yes"
	fi
done
set -e

if [ ! -d "$ROOTDIR/build/toolchain" ]; then
	mkdir -p "$ROOTDIR/build/toolchain"
	cd "$ROOTDIR/build/toolchain"
	wget https://releases.linaro.org/components/toolchain/binaries/7.4-2019.02/aarch64-linux-gnu/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
	rm gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# submodule init
###############################################################################
if [ $MAKE_CLEAN ]; then
	git submodule init
	git submodule update --remote
else

	GIT_CONFIG_FLAG=0
	SUBMODULE_COUNT=0 # Counts the number of definied submodules

	for SUBMODULE_DIR in $(git submodule status|sed 's/^[[:space:]]*//'|cut -d " " -f2); do
		SUBMODULE_COUNT=$(($SUBMODULE_COUNT+1))
		echo -n "Does submodule '$SUBMODULE_DIR' directory exist ? "
		if [ -d "$SUBMODULE_DIR" ]; then
			echo "Yes"
			echo -n "Does submodule '$SUBMODULE_DIR' contain a ''.git' ? "
			if [ -f "$SUBMODULE_DIR/.git" ]; then
				echo "Yes"
				# Flag increments by one everytime an existing git .config file is met
				((GIT_CONFIG_FLAG=$GIT_CONFIG_FLAG+1))
			else
				echo "No"
			fi
		else
			echo "No"
			echo "Missing submodule '$SUBMODULE_DIR', aborting..."
			exit 1
		fi
	done
    echo "Flagged ok -> $GIT_CONFIG_FLAG Total Submodules: $SUBMODULE_COUNT"

	if [[ $GIT_CONFIG_FLAG -ne 0 && $GIT_CONFIG_FLAG -lt $SUBMODULE_COUNT ]]; then
		echo "Partially initialized submodules, trying initialization..."
		git submodule update
	elif [ $GIT_CONFIG_FLAG -eq $SUBMODULE_COUNT ]; then
		echo "Submodules only need updating..."
		git submodule update --recursive
	elif [ $GIT_CONFIG_FLAG -eq 0 ]; then
		echo "Submodules need to be initialized and updated..."
		git submodule update --init
	fi
fi


MCBIN=$( ls $ROOTDIR/build/qoriq-mc-binary/lx2160a/ )

if [ -z $BOOTLOADER_ONLY ]; then

	if [ ! -f "$ROOTDIR/build/ubuntu-core.ext4" ]; then
		cd "$ROOTDIR/build"
		export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C
		export PACKAGES="systemd-sysv apt locales less wget procps openssh-server ifupdown net-tools isc-dhcp-client"
		PACKAGES="$PACKAGES ntpdate lm-sensors i2c-tools psmisc less sudo htop iproute2 iputils-ping kmod network-manager iptables rng-tools"
		# xterm
		cat > ubuntu.conf << EOF
[General]
unpack=true
bootstrap=Ubuntu
aptsources=Ubuntu
cleanup=true
allowrecommends=false
addimportant=false

[Ubuntu]
packages=$PACKAGES
source=http://ports.ubuntu.com/
keyring=ubuntu-keyring
suite=disco
components=main universe multiverse
EOF
		sudo multistrap -a arm64 -d ubuntu -f ubuntu.conf

		sudo sh -c 'echo localhost > ubuntu/etc/hostname'
		sudo sh -c 'sudo cat > ubuntu/etc/hosts << EOF
127.0.0.1 localhost
EOF'
		sudo sh -c 'echo "nameserver 8.8.8.8" > ubuntu/etc/resolv.conf'
	
		QEMU=`which qemu-aarch64-static`

		sudo cp $QEMU ubuntu/usr/bin/

		set +e
		## first configure fails
		sudo chroot ubuntu/ /usr/bin/qemu-aarch64-static /usr/bin/dpkg --configure -a
		set -e
		sudo chroot ubuntu/ /usr/bin/qemu-aarch64-static /usr/bin/dpkg --configure -a
	
		echo -e "root\nroot" | sudo chroot ubuntu/ /usr/bin/qemu-aarch64-static /usr/bin/passwd
		# Remove qemu after done
		sudo rm ubuntu/usr/bin/qemu-aarch64-static
		truncate -s 350M ubuntu-core.ext4.tmp
		mkfs.ext4 -b 4096 -F ubuntu-core.ext4.tmp
		mkdir -p mnt
		sudo mount -o loop ubuntu-core.ext4.tmp mnt/
		sudo cp -a ubuntu/* mnt/
		sudo umount mnt/
		rmdir mnt/
		mv ubuntu-core.ext4.tmp ubuntu-core.ext4
	fi

	if [ ! -d "$ROOTDIR/build/buildroot" ]; then
		cd $ROOTDIR/build
		git clone https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
	fi

	###############################################################################
	# building sources
	###############################################################################


	echo "Building buildroot"
	cd "$ROOTDIR/build/buildroot"
	cp "$ROOTDIR/configs/buildroot/lx2160acex7_defconfig configs/"
	make lx2160acex7_defconfig
	make source -j${PARALLEL}
	make -j${PARALLEL}

	echo "Building restool" # FIX: Restool is not listed in the .gitmodules
	cd "$ROOTDIR/build/restool"
	CC=${CROSS_COMPILE}gcc DESTDIR=./install prefix=/usr make install

fi #BOOTLOADER_ONLY

#####################################################
# Building RCW
#####################################################


echo "Building RCW"
cd $ROOTDIR/build/rcw/lx2160acex7
export SP1 SP2 SP3
IFS=_ read SP1 SP2 SP3 <<< $SERDES

if [ "$SP1" == "4" ]; then
	export SRC1="0"
	export SCL1="0"
	export SPD1="1"
else
	export SRC1="1"
	export SCL1="2"
	export SPD1="1"
fi

envsubst < configs/lx2160a_serdes.def > configs/lx2160a_serdes.rcwi

IFS=_ read CPU SYS MEM <<< $SPEED
export CPU=${CPU::2}
export SYS=$(( 2*${SYS::1} ))
export MEM=${MEM::2}

envsubst < configs/lx2160a_timings.def > configs/lx2160a_timings.rcwi

# Always rebuild the rcws to catch timing changes

rm -f rcws/*.bin
make -j${PARALLEL}

if [ "$BOOT_LOADER" == "u-boot" ]; then

	echo "Build u-boot"
	cd $ROOTDIR/build/u-boot

	if [ $MAKE_CLEAN ]; then
		make distclean
	fi

	if [ ! -f "$ROOTDIR/build/u-boot/.config" ]; then
		make lx2160acex7_tfa_defconfig
	fi

	make -j${PARALLEL}
	export BL33="$ROOTDIR/build/u-boot/u-boot.bin"

fi

###########################################################
# Build UEFI Bootloader
###########################################################

if [ "$BOOT_LOADER" == "uefi" ]; then
	echo "Building UEFI"
	cd "$ROOTDIR/build/tianocore"
	# set the aarch64-linux-gnu cross compiler to the oldie 4.9 linaro toolchain (UEFI build requirement)
	PYTHON_COMMAND=/usr/bin/python3 make -C "$ROOTDIR/build/tianocore/edk2/BaseTools"
	export GCC5_AARCH64_PREFIX=$CROSS_COMPILE
	export WORKSPACE="$ROOTDIR/build/tianocore"
	export PACKAGES_PATH="$WORKSPACE/edk2:$WORKSPACE/edk2-platforms:$WORKSPACE/edk2-non-osi"
  	source  edk2/edksetup.sh
	if [ $MAKE_CLEAN ]; then
		echo "Cleaning UEFI build..." 
		build -p "edk2-platforms/Platform/SolidRun/LX2160aCex7/LX2160aCex7.dsc" -a AARCH64 -t GCC5 -b $UEFI_RELEASE -y build.log clean
	fi
	build -p "edk2-platforms/Platform/SolidRun/LX2160aCex7/LX2160aCex7.dsc" -a AARCH64 -t GCC5 -b $UEFI_RELEASE -y build.log
	export BL33="$ROOTDIR/build/tianocore/Build/LX2160aCex7/${UEFI_RELEASE}_GCC5/FV/LX2160ACEX7_EFI.fd"
	export ARCH=arm64 # While building UEFI ARCH is unset
fi

echo "Building arm-trusted-firmware"
cd "$ROOTDIR/build/arm-trusted-firmware/"

if [ $MAKE_CLEAN ]; then
	make PLAT=lx2160acex7 clean
fi

if [ "${BOOT}" == "sd" ]; then
	ATF_BOOT=sd
else
	ATF_BOOT=flexspi_nor
fi

make -j${PARALLEL} PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/rcws/rcw_${BOOT}.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=${ATF_BOOT} SECURE_BOOT=false

echo "Building mc-utils"
cd $ROOTDIR/build/mc-utils
make -C config/

if [ -z "$BOOTLOADER_ONLY" ]; then

	echo "Building the kernel"
	cd $ROOTDIR/build/linux

	if [ $MAKE_CLEAN ]; then
		make -j${PARALLEL} distclean #Image dtbs
	fi

	if [ ! -f "$ROOTDIR/build/linux/.config" ]; then
		./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig arch/arm64/configs/lsdk.config "$ROOTDIR/configs/linux/lx2k_additions.config"
	fi

	make -j${PARALLEL} all #Image dtbs
	mkimage -f $ROOTDIR/files/kernel2160cex7.its kernel-lx2160acex7.itb
	\rm -rf $ROOTDIR/images/tmp
	mkdir -p $ROOTDIR/images/tmp/
	mkdir -p $ROOTDIR/images/tmp/boot
	make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/ modules_install
	cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/boot
	cp $ROOTDIR/build/linux/arch/arm64/boot/dts/freescale/fsl-lx2160a-cex7.dtb $ROOTDIR/images/tmp/boot

	###############################################################################
	# assembling images
	###############################################################################

	echo "Assembling kernel and rootfs image"
	cd $ROOTDIR
	mkdir -p $ROOTDIR/images/tmp/extlinux/

	cat > $ROOTDIR/images/tmp/extlinux/extlinux.conf << EOF
  TIMEOUT 30
  DEFAULT linux
  MENU TITLE linux-lx2160a boot options
  LABEL primary
    MENU LABEL primary kernel
    LINUX /boot/Image
    FDT /boot/fsl-lx2160a-cex7.dtb
    APPEND console=ttyAMA0,115200 earlycon=pl011,mmio32,0x21c0000 default_hugepagesz=1024m hugepagesz=1024m hugepages=2 pci=pcie_bus_perf root=PARTUUID=30303030-01 rw rootwait
EOF

	# blkid images/tmp/ubuntu-core.img | cut -f2 -d'"'

	cp $ROOTDIR/build/ubuntu-core.ext4 $ROOTDIR/images/tmp/
	e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:extlinux
	e2cp -G 0 -O 0 $ROOTDIR/images/tmp/extlinux/extlinux.conf $ROOTDIR/images/tmp/ubuntu-core.ext4:extlinux/
	e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:boot
	e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/Image $ROOTDIR/images/tmp/ubuntu-core.ext4:boot/
	e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/fsl-lx2160a-cex7.dtb $ROOTDIR/images/tmp/ubuntu-core.ext4:boot/

	# install restool

	e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-append-dpl $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
	e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-main $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
	e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/restool $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
	e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addmux
	e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addni
	e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addsw
	e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-listmac
	e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-listni

	truncate -s 356M $ROOTDIR/images/tmp/ubuntu-core.img
	parted --script $ROOTDIR/images/tmp/ubuntu-core.img mklabel msdos mkpart primary 1MiB 354MiB
	# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
	echo "0000" | dd of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1 seek=440 conv=notrunc
	dd if=$ROOTDIR/images/tmp/ubuntu-core.ext4 of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1M seek=1 conv=notrunc
	### TODO - copy over kernel modules
	### TODO - copy /etc/resolv.conf

  #####################################################
	# Boot Image Assembling
  #####################################################

	echo "Assembling Boot Image"
	cd "$ROOTDIR/"
	IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT}.img
	truncate -s 465M $ROOTDIR/images/${IMG}
	#dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=1
	parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB 464MiB
	truncate -s 400M $ROOTDIR/images/tmp/boot.part
	mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
	e2cp -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.img $ROOTDIR/images/tmp/boot.part:/
	dd if=$ROOTDIR/images/tmp/boot.part of=$ROOTDIR/images/${IMG} bs=1M seek=64
else
	cd "$ROOTDIR/"
	IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT}.img
	dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=16
fi

# RCW+PBI+BL2 at block 8

if [ "${BOOT}" == "sd" ]; then
	dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc
else
	dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 conv=notrunc
fi

# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800

dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000

dd if=$ROOTDIR/build/ddr-phy-binary/lx2160a/fip_ddr.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc

# Env variables at 0x2800

# Secureboot headers at 0x3000

# DPAA1 FMAN ucode at 0x4800

# DPAA2-MC at 0x5000
dd if=$ROOTDIR/build/qoriq-mc-binary/lx2160a/${MCBIN} of=images/${IMG} bs=512 seek=20480 conv=notrunc

# DPAA2 DPL at 0x6800
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPL} of=images/${IMG} bs=512 seek=26624 conv=notrunc

# DPAA2 DPC at 0x7000
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPC} of=images/${IMG} bs=512 seek=28672 conv=notrunc

if [ -z "$BOOTLOADER_ONLY"  ]; then
# Kernel at 0x8000
dd if=$ROOTDIR/build/linux/kernel-lx2160acex7.itb of=images/${IMG} bs=512 seek=32768 conv=notrunc
fi

# Ramdisk at 0x10000

