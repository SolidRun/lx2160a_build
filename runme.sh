#!/bin/bash
set -e

# BOOT_LOADER=u-boot,uefi
# DDR_SPEED=2400,2600,2900,3200
# SERDES=8_5_2, 13_5_2, 20_5_2

###############################################################################
# General configurations
###############################################################################
#RELEASE=lx2160a-early-access-bsp0.7 # Supports both rev1 and rev2
#RELEASE=LSDK-19.09 # LSDK-19.09 supports rev1 only
BUILDROOT_VERSION=2020.02.1
#UEFI_RELEASE=DEBUG
#BOOT_LOADER=uefi
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g
###############################################################################
# Misc
###############################################################################
RELEASE=${RELEASE:-LSDK-20.04}
BOOT_LOADER=${BOOT_LOADER:-u-boot}
DDR_SPEED=${DDR_SPEED:-3200}
SERDES=${SERDES:-8_5_2}
UEFI_RELEASE=${UEFI_RELEASE:-RELEASE}

mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=2000_700_${DDR_SPEED}
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 parted mkdosfs mcopy dtc iasl mkimage e2cp truncate qemu-system-aarch64 cpio rsync bc bison flex python unzip"

export PATH=$ROOTDIR/build/toolchain/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

case "${SERDES}" in
	8_*)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	13_*)
		DPC=dpc-dual-100g.dtb
		DPL=dpl-eth.dual-100g.19.dtb
	;;
	20_*)
		DPC=dpc-dual-40g.dtb
		DPL=dpl-eth.dual-40g.19.dtb
	;;
	*)
		echo "Please define SERDES configuration"
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
		echo "sudo apt install build-essential git dosfstools e2fsprogs parted sudo mtools p7zip p7zip-full device-tree-compiler acpica-tools u-boot-tools e2tools qemu-system-arm libssl-dev cpio rsync bc bison flex python unzip"
		exit -1
	fi
done
set -e

# Check if git is configured
GIT_CONF=`git config user.name`
if [ "x$GIT_CONF" == "x" ]; then
	echo "git is not configured. please configure git username and email first"
	exit -1
fi

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
QORIQ_COMPONENTS="u-boot atf rcw restool mc-utils linux dpdk"
for i in $QORIQ_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		echo "Cloing https://source.codeaurora.org/external/qoriq/qoriq-components/$i release $RELEASE"
		cd $ROOTDIR/build
		git clone https://source.codeaurora.org/external/qoriq/qoriq-components/$i
		cd $i
		if [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-19.06" ]; then
			git checkout -b LSDK-19.06-V4.19 refs/tags/LSDK-19.06-V4.19
		elif [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-19.09" ]; then
			git checkout -b LSDK-19.09-V4.19
		elif [ "x$i" == "xlinux" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			git checkout -b LSDK-20.04-V5.4 refs/tags/LSDK-20.04-V5.4
		elif [ "x$i" == "xdpdk" ] && [ "x$RELEASE" == "xLSDK-20.04" ]; then
			git checkout -b LSDK-19.09
		elif [ "x$i" == "xrestool" ] && [ "x$RELEASE" == "xLSDK-19.06" ]; then
			git checkout -b LSDK-19.09-update-291119
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
		if [[ -d $ROOTDIR/patches/$i-$RELEASE/ ]]; then
			git am $ROOTDIR/patches/$i-$RELEASE/*.patch
		fi
	fi
done


if [[ ! -f $ROOTDIR/build/ubuntu-core.ext4 ]]; then
	cd $ROOTDIR/build
	mkdir -p ubuntu
	cd ubuntu
	if [ ! -d buildroot ]; then
		git clone https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
	fi
	cd buildroot
	cp $ROOTDIR/configs/buildroot/lx2160acex7_defconfig configs/
	make lx2160acex7_defconfig
	mkdir -p overlay/etc/init.d/
	cat > overlay/etc/init.d/S99bootstrap-ubuntu.sh << EOF
#!/bin/sh

case "\$1" in
	start)
		resize
		mkfs.ext4 -F /dev/vda -b 4096
		mount /dev/vda /mnt
		cd /mnt/
		udhcpc -i eth0
		wget -c -P /tmp/ http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04-base-arm64.tar.gz
		tar zxf /tmp/ubuntu-base-20.04-base-arm64.tar.gz -C /mnt
		mount -o bind /proc /mnt/proc/
		mount -o bind /sys/ /mnt/sys/
		mount -o bind /dev/ /mnt/dev/
		mount -o bind /dev/pts /mnt/dev/pts
		mount -t tmpfs tmpfs /mnt/var/lib/apt/
		mount -t tmpfs tmpfs /mnt/var/cache/apt/
		echo "nameserver 8.8.8.8" > /mnt/etc/resolv.conf
		echo "localhost" > /mnt/etc/hostname
		echo "127.0.0.1 localhost" > /mnt/etc/hosts
		export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C
		chroot /mnt apt update
		chroot /mnt apt install --no-install-recommends -y systemd-sysv apt locales less wget procps openssh-server ifupdown net-tools isc-dhcp-client ntpdate lm-sensors i2c-tools psmisc less sudo htop iproute2 iputils-ping kmod network-manager iptables rng-tools apt-utils
		echo -e "root\nroot" | chroot /mnt passwd
		umount /mnt/var/lib/apt/
		umount /mnt/var/cache/apt
		chroot /mnt apt clean
		chroot /mnt apt autoclean
		reboot
		;;
esac
EOF
	chmod +x overlay/etc/init.d/S99bootstrap-ubuntu.sh
	make
	IMG=ubuntu-core.ext4.tmp
	truncate -s 350M $IMG
	qemu-system-aarch64 -m 1G -M virt -cpu cortex-a57 -nographic -smp 1 -kernel output/images/Image -append "console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -initrd output/images/rootfs.cpio.gz -drive file=$IMG,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -no-reboot
	mv $IMG $ROOTDIR/build/ubuntu-core.ext4
fi

if [[ ! -d $ROOTDIR/build/qoriq-mc-binary ]]; then
	cd $ROOTDIR/build
	git clone https://github.com/NXP/qoriq-mc-binary.git
	cd qoriq-mc-binary
	git checkout -b $RELEASE refs/tags/$RELEASE
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
echo "#include <configs/lx2160a_defaults.rcwi>" > RCW/template.rcw
echo "#include <configs/lx2160a_${SPEED}.rcwi>" >> RCW/template.rcw
echo "#include <configs/lx2160a_${SERDES}.rcwi>" >> RCW/template.rcw
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
make -j${PARALLEL} PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/RCW/template.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=auto SECURE_BOOT=false

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
			data = /incbin/("../../patches/linux-${RELEASE}/ramdisk_rootfs_arm64.ext4.gz");
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
make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/ INSTALL_MOD_STRIP=1 modules_install
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/freescale/fsl-lx2160a-cex7.dtb $ROOTDIR/images/tmp/boot



echo "Building DPDK"
cd $ROOTDIR/build/dpdk
export CROSS=$CROSS_COMPILE
export RTE_SDK=$ROOTDIR/build/dpdk
export DESTDIR=$ROOTDIR/build/dpdk/install
export RTE_TARGET=arm64-dpaa2-linuxapp-gcc
#make -j32 T=arm64-dpaa2-linuxapp-gcc CONFIG_RTE_KNI_KMOD=n CONFIG_RTE_LIBRTE_PMD_OPENSSL=n clean
make -j32 T=arm64-dpaa2-linuxapp-gcc CONFIG_RTE_KNI_KMOD=n CONFIG_RTE_LIBRTE_PMD_OPENSSL=n install
make -j32 T=arm64-dpaa2-linuxapp-gcc CONFIG_RTE_KNI_KMOD=n CONFIG_RTE_LIBRTE_PMD_OPENSSL=n -C examples/l2fwd install
make -j32 T=arm64-dpaa2-linuxapp-gcc CONFIG_RTE_KNI_KMOD=n CONFIG_RTE_LIBRTE_PMD_OPENSSL=n -C examples/l3fwd install


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

# Copy over kernel image
echo "Copying kernel modules"
cd $ROOTDIR/images/tmp/
for i in `find lib`; do
	if [ -d $i ]; then
		e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:usr/$i
	fi
	if [ -f $i ]; then
		DIR=`dirname $i`
		e2cp -G 0 -O 0 -p $ROOTDIR/images/tmp/$i $ROOTDIR/images/tmp/ubuntu-core.ext4:usr/$DIR
	fi
done
cd -

# install restool
echo "Install restool"
cd $ROOTDIR/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-append-dpl $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/ls-main $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
e2cp -p -G 0 -O 0 $ROOTDIR/build/restool/install/usr/bin/restool $ROOTDIR/images/tmp/ubuntu-core.ext4:/usr/bin/
e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addmux
e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addni
e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-addsw
e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-listmac
e2ln images/tmp/ubuntu-core.ext4:/usr/bin/ls-main /usr/bin/ls-listni

truncate -s 420M $ROOTDIR/images/tmp/ubuntu-core.img
parted --script $ROOTDIR/images/tmp/ubuntu-core.img mklabel msdos mkpart primary 64MiB 417MiB
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/ubuntu-core.ext4 of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1M seek=64 conv=notrunc

echo "Assembling Boot Image"
cd $ROOTDIR/
IMG=lx2160acex7_${SPEED}_${SERDES}.img
rm -rf $ROOTDIR/images/${IMG}
truncate -s 528M $ROOTDIR/images/${IMG}
#dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=1
parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB 527MiB
truncate -s 463M $ROOTDIR/images/tmp/boot.part
mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
\rm -rf $ROOTDIR/images/tmp/xspi_header.img
truncate -s 128K $ROOTDIR/images/tmp/xspi_header.img
dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/bl2_auto.pbl of=$ROOTDIR/images/tmp/xspi_header.img bs=512 conv=notrunc
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/xspi_header.img $ROOTDIR/images/tmp/boot.part:/

# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000
dd if=$ROOTDIR/build/atf/tools/fiptool/fip_ddr_all.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
# Env variables at 0x2800

# Secureboot headers at 0x3000

# DPAA1 FMAN ucode at 0x4800

# DPAA2-MC at 0x5000
if [ "x$RELEASE" == "xLSDK-19.09" ]; then
	MC=mc_10.18.0_lx2160a.itb
elif [ "x$RELEASE" == "xlx2160a-early-access-bsp0.7" ]; then
	MC=mc_10.20.1_lx2160a.itb
else
	MC=`ls $ROOTDIR/build/qoriq-mc-binary/lx2160a/ | cut -f1`
fi
dd if=$ROOTDIR/build/qoriq-mc-binary/lx2160a/${MC} of=images/${IMG} bs=512 seek=20480 conv=notrunc

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
# RCW+PBI+BL2 at block 8
dd if=$ROOTDIR/images/${IMG} of=$ROOTDIR/images/lx2160acex7_xspi_${SPEED}_${SERDES}.img bs=1M count=64
dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/bl2_auto.pbl of=images/lx2160acex7_xspi_${SPEED}_${SERDES}.img bs=512 conv=notrunc
dd if=$ROOTDIR/build/atf/build/lx2160acex7/release/bl2_auto.pbl of=images/${IMG} bs=512 seek=8 conv=notrunc

# Copy first 64MByte from image excluding MBR to ubuntu-core.img for eMMC boot
dd if=images/${IMG} of=$ROOTDIR/images/tmp/ubuntu-core.img bs=512 seek=1 skip=1 count=131071 conv=notrunc
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.img $ROOTDIR/images/tmp/boot.part:/
dd if=$ROOTDIR/images/tmp/boot.part of=$ROOTDIR/images/${IMG} bs=1M seek=64
