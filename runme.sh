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
mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=2000_700_${DDR_SPEED}
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 sudo parted mkdosfs mcopy dtc iasl mkimage e2cp truncate multistrap qemu-aarch64-static"

export PATH=$ROOTDIR/build/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
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
	wget https://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/aarch64-linux-gnu/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu.tar.xz
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# source code cloning
###############################################################################
QORIQ_COMPONENTS="u-boot atf rcw uefi restool mc-utils linux"
for i in $QORIQ_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		echo "Cloing https://source.codeaurora.org/external/qoriq/qoriq-components/$i release $RELEASE"
		cd $ROOTDIR/build
		git clone https://source.codeaurora.org/external/qoriq/qoriq-components/$i
		cd $i
		if [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-19.06" ]; then
			git checkout -b LSDK-19.06-V4.19 refs/tags/LSDK-19.06-V4.19
		else
			git checkout -b $RELEASE refs/tags/$RELEASE
		fi
		if [ "x$i" == "xatf" ]; then
			cd $ROOTDIR/build/atf/tools/fiptool
			git clone https://github.com/NXP/ddr-phy-binary.git
			make
			./fiptool create --ddr-immem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_imem.bin --ddr-immem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_imem.bin --ddr-dmmem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_dmem.bin --ddr-dmmem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_dmem.bin --ddr-immem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_imem.bin --ddr-immem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_imem.bin --ddr-dmmem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_dmem.bin --ddr-dmmem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_dmem.bin fip_ddr_all.bin
		fi
		if [ "x$i" == "xuefi" ]; then
			cd $ROOTDIR/build/uefi/
			git clone https://source.codeaurora.org/external/qoriq/qoriq-components/edk2-platforms
			cd edk2-platforms
			git checkout -b $RELEASE refs/tags/$RELEASE
			patch -p1 < $ROOTDIR/patches/edk2-platforms/*.diff
			git am --keep-cr $ROOTDIR/patches/edk2-platforms/*.patch
		fi
		if [[ -d $ROOTDIR/patches/$i/ ]]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
	fi
done

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

if [[ ! -d $ROOTDIR/build/qoriq-mc-binary ]]; then
	cd $ROOTDIR/build
	git clone https://github.com/NXP/qoriq-mc-binary.git
	cd qoriq-mc-binary
	git checkout -b $RELEASE refs/tags/$RELEASE
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
make

echo "Building restool"
cd $ROOTDIR/build/restool
CC=${CROSS_COMPILE}gcc DESTDIR=./install prefix=/usr make install

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
	cd $ROOTDIR/build/uefi
	# set the aarch64-linux-gnu cross compiler to the oldie 4.9 linaro toolchain (UEFI build requirement)
	PATH_SAVED=$PATH
	export PATH=$ROOTDIR/build/toolchain/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu/bin/:$PATH
	source  edksetup.sh
	cd edk2-platforms/Platform/NXP
	source Env.cshrc
	make -C $ROOTDIR/build/uefi/BaseTools/Source/C
#	./build.sh LX2160 RDB RELEASE clean
#	./build.sh LX2160 RDB RELEASE
#	export BL33=$ROOTDIR/build/uefi/Build/LX2160aRdbPkg/RELEASE_GCC49/FV/LX2160ARDB_EFI.fd
#	build -p "$PACKAGES_PATH/Platform/NXP/LX2160aRdbPkg/LX2160aRdbPkg.dsc" -a AARCH64 -t GCC49 -b DEBUG
#	export BL33=$ROOTDIR/build/uefi/Build/LX2160aRdbPkg/RELEASE_GCC49/FV/LX2160ARDB_EFI.fd
#	export BL33=$ROOTDIR/build/uefi/Build/LX2160aRdbPkg/DEBUG_GCC49/FV/LX2160ARDB_EFI.fd

#	build -p "$PACKAGES_PATH/Platform/NXP/LX2160aCex7Pkg/LX2160aCex7Pkg.dsc" -a AARCH64 -t GCC49 -b DEBUG clean

#	build -p "$PACKAGES_PATH/Platform/NXP/LX2160aCex7Pkg/LX2160aCex7Pkg.dsc" -a AARCH64 -t GCC49 -b $UEFI_RELEASE clean
	build -p "$PACKAGES_PATH/Platform/NXP/LX2160aCex7Pkg/LX2160aCex7Pkg.dsc" -a AARCH64 -t GCC49 -b $UEFI_RELEASE -y build.log
	export BL33=$ROOTDIR/build/uefi/Build/LX2160aCex7Pkg/${UEFI_RELEASE}_GCC49/FV/LX2160ACEX7_EFI.fd

	# Return to the newer linaro gcc
	export PATH=$PATH_SAVED
	export ARCH=arm64 # While building UEFI ARCH is unset
fi

echo "Building atf"
cd $ROOTDIR/build/atf/
make PLAT=lx2160acex7 clean
#make -j32 PLAT=lx2160acex7 all fip pbl BL33=$ROOTDIR/build/u-boot/u-boot.bin RCW=$ROOTDIR/build/rcw/lx2160acex7/XGGFF_PP_HHHH_RR_19_5_2/rcw_${SPEED}_8_5_2_${BOOT}.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=sd SECURE_BOOT=false
if [ "x${BOOT}" == "xsd" ]; then
	ATF_BOOT=sd
else
	ATF_BOOT=flexspi_nor
fi
make -j${PARALLEL} PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/XGGFF_PP_HHHH_RR_19_5_2/rcw_${SPEED}_${SERDES}_${BOOT}.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=${ATF_BOOT} SECURE_BOOT=false

echo "Building mc-utils"
cd $ROOTDIR/build/mc-utils
make -C config/


echo "Building the kernel"
cd $ROOTDIR/build/linux
./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig arch/arm64/configs/lsdk.config $ROOTDIR/configs/linux/lx2k_additions.config
make -j${PARALLEL} all #Image dtbs

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
			data = /incbin/("../../patches/linux/ramdisk_rootfs_arm64.ext4.gz");
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
			data = /incbin/("arch/arm64/boot/dts/freescale/fsl-lx2160a-cex7.dtb");
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

# RCW+PBI+BL2 at block 8
if [ "x${BOOT}" == "xsd" ]; then
	dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc
else
	dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/bl2_${ATF_BOOT}.pbl of=images/${IMG} bs=512 conv=notrunc
fi
# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000
dd if=$ROOTDIR/build/atf/tools/fiptool/fip_ddr_all.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
# Env variables at 0x2800

# Secureboot headers at 0x3000

# DPAA1 FMAN ucode at 0x4800

# DPAA2-MC at 0x5000
dd if=$ROOTDIR/build/qoriq-mc-binary/lx2160a/mc_10.16.2_lx2160a.itb of=images/${IMG} bs=512 seek=20480 conv=notrunc

# DPAA2 DPL at 0x6800
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPL} of=images/${IMG} bs=512 seek=26624 conv=notrunc

# DPAA2 DPC at 0x7000
dd if=$ROOTDIR/build/mc-utils/config/lx2160a/CEX7/${DPC} of=images/${IMG} bs=512 seek=28672 conv=notrunc

# Device tree (UEFI) at 0x7800
if [ "x${BOOT_LOADER}" == "xuefi" ]; then
	dd if=$ROOTDIR/build/uefi/Build/LX2160aCex7Pkg/${UEFI_RELEASE}_GCC49/AARCH64/Platform/NXP/LX2160aCex7Pkg/DeviceTree/DeviceTree/OUTPUT/fsl-lx2160a-cex7.dtb of=images/${IMG} bs=512 seek=30720 conv=notrunc
	dd if=$ROOTDIR/build/uefi/Build/LX2160aCex7Pkg/${UEFI_RELEASE}_GCC49/FV/LX2160ACEX7NV_EFI.fd of=images/${IMG} bs=512 seek=10240 conv=notrunc
fi
# Kernel at 0x8000
dd if=$ROOTDIR/build/linux/kernel-lx2160acex7.itb of=images/${IMG} bs=512 seek=32768 conv=notrunc

# Ramdisk at 0x10000

