#!/bin/bash
set -e

# BOOT=sd,xspi
# BOOT_LOADER=u-boot,uefi
# DDR_SPEED=2400,2600,2900,3200
# SERDES=8_5_2, 13_5_2, 20_5_2

###############################################################################
# General configurations
###############################################################################
RELEASE=LSDK-19.06
BUILDROOT_VERSION=2019.05.2

#UEFI_RELEASE=DEBUG
#BOOT=xspi
#BOOT_LOADER=uefi
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g
###############################################################################
# Misc
###############################################################################
if [ "x$BOOT" == "x" ]; then
	BOOT=sd
fi

if [ "x$BOOT_LOADER" == "x" ]; then
	BOOT_LOADER=u-boot
fi

if [ "x$DDR_SPEED" == "x" ]; then
	DDR_SPEED=3200
fi
if [ "x$SERDES" == "x" ]; then
	SERDES=8_5_2
fi
if [ "x$UEFI_RELEASE" == "x" ]; then
	UEFI_RELEASE=RELEASE
fi
mkdir -p images/tmp
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=2000_700_${DDR_SPEED}

if [ "x$BOOTLOADER_ONLY" != "x" ]; then
TOOLS="wget tar git make dd dtc iasl"
else
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 sudo parted mkdosfs mcopy dtc iasl mkimage e2cp truncate multistrap qemu-aarch64-static"
fi

export CROSS_COMPILE=$ROOTDIR/build/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
export ARCH=arm64

if [ "x$SERDES" == "x" ]; then
	echo "Please define SERDES configuration"
	exit -1
fi
if [ "x${SERDES:0:3}" == "x13_" ]; then
	DPC=dpc-dual-100g.dtb
	DPL=dpl-eth.dual-100g.19.dtb
fi
if [ "x${SERDES:0:2}" == "x8_" ]; then
	DPC=dpc-8_x_usxgmii.dtb 
	DPL=dpl-eth.8x10g.19.dtb
fi
if [ "x${SERDES:0:3}" == "x20_" ]; then
	DPC=dpc-dual-40g.dtb
	DPL=dpl-eth.dual-40g.19.dtb
fi

echo "Checking all required tools are installed"

set +e
for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		exit -1
	fi
done
set -e

if [[ ! -d $ROOTDIR/build/toolchain ]]; then
	mkdir -p $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget https://releases.linaro.org/components/toolchain/binaries/7.4-2019.02/aarch64-linux-gnu/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
	rm gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# submodule init
###############################################################################
git submodule init
git submodule update --remote

MCBIN=$( ls $ROOTDIR/build/qoriq-mc-binary/lx2160a/ )

make -C $ROOTDIR/build/arm-trusted-firmware/tools/fiptool
$ROOTDIR/build/arm-trusted-firmware/tools/fiptool/fiptool create --ddr-immem-udimm-1d build/ddr-phy-binary/lx2160a/ddr4_pmu_train_imem.bin --ddr-immem-udimm-2d build/ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_imem.bin --ddr-dmmem-udimm-1d build/ddr-phy-binary/lx2160a/ddr4_pmu_train_dmem.bin --ddr-dmmem-udimm-2d build/ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_dmem.bin --ddr-immem-rdimm-1d build/ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_imem.bin --ddr-immem-rdimm-2d build/ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_imem.bin --ddr-dmmem-rdimm-1d build/ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_dmem.bin --ddr-dmmem-rdimm-2d build/ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_dmem.bin images/tmp/fip_ddr_all.bin

if [ "x$BOOTLOADER_ONLY" == "x" ]; then
if [[ ! -f $ROOTDIR/build/ubuntu-core.ext4 ]]; then
	cd $ROOTDIR/build
	export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C
	export PACKAGES="systemd-sysv apt locales less wget procps openssh-server ifupdown net-tools isc-dhcp-client"
	PACKAGES=$PACKAGES" ntpdate lm-sensors i2c-tools psmisc less sudo htop iproute2 iputils-ping kmod network-manager iptables rng-tools"
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

if [[ ! -d $ROOTDIR/build/buildroot ]]; then
	cd $ROOTDIR/build
	git clone https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
fi
###############################################################################
# building sources
###############################################################################


echo "Building buildroot"
cd $ROOTDIR/build/buildroot
cp $ROOTDIR/configs/buildroot/lx2160acex7_defconfig configs/
make lx2160acex7_defconfig
make source -j${PARALLEL}
make -j${PARALLEL}

echo "Building restool"
cd $ROOTDIR/build/restool
CC=${CROSS_COMPILE}gcc DESTDIR=./install prefix=/usr make install
fi #BOOTLOADER_ONLY

echo "Building RCW"
cd $ROOTDIR/build/rcw/lx2160acex7
make clean
make -j${PARALLEL}

if [ "x$BOOT_LOADER" == "xu-boot" ]; then
	echo "Build u-boot"
	cd $ROOTDIR/build/u-boot
	#make distclean
	make lx2160acex7_tfa_defconfig
	make -j${PARALLEL}
	export BL33=$ROOTDIR/build/u-boot/u-boot.bin
fi

if [ "x$BOOT_LOADER" == "xuefi" ]; then
	echo "Build UEFI"
	cd $ROOTDIR/build/tianocore
	# set the aarch64-linux-gnu cross compiler to the oldie 4.9 linaro toolchain (UEFI build requirement)
	make -C $ROOTDIR/build/tianocore/edk2/BaseTools
	export GCC5_AARCH64_PREFIX=$CROSS_COMPILE
	export WORKSPACE=$ROOTDIR/build/tianocore
	export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms
	source  edk2/edksetup.sh
	build -p "edk2-platforms/Platform/NXP/LX2160aCex7Pkg/LX2160aCex7Pkg.dsc" -a AARCH64 -t GCC5 -b $UEFI_RELEASE -y build.log
	export BL33=$ROOTDIR/build/tianocore/Build/LX2160aCex7Pkg/${UEFI_RELEASE}_GCC5/FV/LX2160ACEX7_EFI.fd
	export ARCH=arm64 # While building UEFI ARCH is unset
fi

echo "Building arm-trusted-firmware"
cd $ROOTDIR/build/arm-trusted-firmware/

make PLAT=lx2160acex7 clean

if [ "x${BOOT}" == "xsd" ]; then
	ATF_BOOT=sd
else
	ATF_BOOT=flexspi_nor
fi

make -j${PARALLEL} PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/XGGFF_PP_HHHH_RR_19_5_2/rcw_${SPEED}_${SERDES}_${BOOT}.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=${ATF_BOOT} SECURE_BOOT=false

echo "Building mc-utils"
cd $ROOTDIR/build/mc-utils
make -C config/


if [ "x$BOOTLOADER_ONLY" == "x" ]; then
echo "Building the kernel"
cd $ROOTDIR/build/linux
./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig arch/arm64/configs/lsdk.config $ROOTDIR/configs/linux/lx2k_additions.config
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

echo "Assembling Boot Image"
cd $ROOTDIR/
IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT}.img
truncate -s 465M $ROOTDIR/images/${IMG}
#dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=1
parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB 464MiB
truncate -s 400M $ROOTDIR/images/tmp/boot.part
mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.img $ROOTDIR/images/tmp/boot.part:/
dd if=$ROOTDIR/images/tmp/boot.part of=$ROOTDIR/images/${IMG} bs=1M seek=64
else
cd $ROOTDIR/
IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT}.img
dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=16
fi
# RCW+PBI+BL2 at block 8
if [ "x${BOOT}" == "xsd" ]; then
	dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc
else
	dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 conv=notrunc
fi
# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000
dd if=$ROOTDIR/images/tmp/fip_ddr_all.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
# Env variables at 0x2800

# Secureboot headers at 0x3000

# DPAA1 FMAN ucode at 0x4800

# DPAA2-MC at 0x5000
dd if=$ROOTDIR/build/qoriq-mc-binary/lx2160a/${MCBIN} of=images/${IMG} bs=512 seek=20480 conv=notrunc

# DPAA2 DPL at 0x6800
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPL} of=images/${IMG} bs=512 seek=26624 conv=notrunc

# DPAA2 DPC at 0x7000
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPC} of=images/${IMG} bs=512 seek=28672 conv=notrunc

if [ "x$BOOTLOADER_ONLY" == "x" ]; then
# Kernel at 0x8000
dd if=$ROOTDIR/build/linux/kernel-lx2160acex7.itb of=images/${IMG} bs=512 seek=32768 conv=notrunc
fi

# Ramdisk at 0x10000

