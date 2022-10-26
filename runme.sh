#!/bin/bash
set -e

###############################################################################
# General configurations
###############################################################################
BUILDROOT_VERSION=2020.02.1
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g

###############################################################################
# Misc
###############################################################################
: ${RELEASE:=LSDK-21.08}
: ${DDR_SPEED:=3200}
: ${SERDES:=8_5_2}
: ${UEFI_RELEASE:=RELEASE}
: ${SHALLOW:=false}
: ${SECURE:=false}
: ${ATF_DEBUG:=false}
: ${DISTRO:=ubuntu}
: ${BR2_PRIMARY_SITE:=} # custom buildroot mirror

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

mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=2000_700_${DDR_SPEED}
TOOLS="tar git make 7z dd mkfs.ext4 parted mkdosfs mcopy dtc iasl mkimage e2cp truncate qemu-system-aarch64 cpio rsync bc bison flex python unzip pandoc meson ninja depmod"
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
		# MC 10.28.1 is incapable of mapping all 16 dpnis. 10.28.100 fixes that
		if [ "x$RELEASE" == "xLSDK-21.08" ]; then
			MC_FORCE=patches/mc_10.28.100_lx2160a.itb
		fi
	;;
	2_*)
		DPC=dpc-8_x_usxgmii.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	4_*)
		DPC=dpc-backplane.dtb
		DPL=dpl-eth.8x10g.19.dtb
	;;
	8_*)
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
	LX2162A_CLEARFOG_0_0_*)
		DPC=LX2162-USOM/clearfog-s1_0-s2_0-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_0-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_0_7_*)
		DPC=LX2162-USOM/clearfog-s1_0-s2_7-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_0-s2_7-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
		MC_FORCE=patches/mc_10.28.100_lx2160a.itb
	;;
	LX2162A_CLEARFOG_0_9_*)
		DPC=LX2162-USOM/clearfog-s1_0-s2_9-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_0-s2_9-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
		MC_FORCE=patches/mc_10.28.100_lx2160a.itb
	;;
	LX2162A_CLEARFOG_0_11_*)
		DPC=LX2162-USOM/clearfog-s1_0-s2_11-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_0-s2_11-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
		MC_FORCE=patches/mc_10.28.100_lx2160a.itb
	;;
	LX2162A_CLEARFOG_3_0_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_0-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_0-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	LX2162A_CLEARFOG_3_9_*)
		DPC=LX2162-USOM/clearfog-s1_3-s2_9-dpc.dtb
		DPL=LX2162-USOM/clearfog-s1_3-s2_9-dpl.dtb
		DEFAULT_FDT_FILE="fsl-lx2162a-clearfog.dtb"
	;;
	*)
		echo "Please define SERDES configuration"
		exit -1
	;;
esac

case "${DDR_SPEED}" in
	2400|2600|2900|3200)
	;;
	*)
		echo "Please use one of allowed DDR speeds: 2400, 2600, 2900, 3200"
		exit -1
	;;
esac

case "${DISTRO}" in
	ubuntu)
		ROOTFS=ubuntu-core
		ROOTFS_SIZE=350M
	;;
	debian)
		ROOTFS=debian-bullseye
		ROOTFS_SIZE=350M
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
QORIQ_COMPONENTS="u-boot atf rcw restool mc-utils linux dpdk cst"
for i in $QORIQ_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		echo "Cloing https://source.codeaurora.org/external/qoriq/qoriq-components/$i release $RELEASE"
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
		git clone $SHALLOW_FLAG https://source.codeaurora.org/external/qoriq/qoriq-components/$i -b $CHECKOUT
		cd $i
		if [ "x$i" == "xatf" ]; then
			cd $ROOTDIR/build/atf/tools/fiptool
			git clone $SHALLOW_FLAG https://github.com/NXP/ddr-phy-binary.git
			make
			./fiptool create --ddr-immem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_imem.bin --ddr-immem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_imem.bin --ddr-dmmem-udimm-1d ddr-phy-binary/lx2160a/ddr4_pmu_train_dmem.bin --ddr-dmmem-udimm-2d ddr-phy-binary/lx2160a/ddr4_2d_pmu_train_dmem.bin --ddr-immem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_imem.bin --ddr-immem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_imem.bin --ddr-dmmem-rdimm-1d ddr-phy-binary/lx2160a/ddr4_rdimm_pmu_train_dmem.bin --ddr-dmmem-rdimm-2d ddr-phy-binary/lx2160a/ddr4_rdimm2d_pmu_train_dmem.bin fip_ddr_all.bin
		fi
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


if [[ ! -f $ROOTDIR/build/ubuntu-core.ext4 ]] && [ "x$DISTRO" == "xubuntu" ]; then
	cd $ROOTDIR/build
	mkdir -p ubuntu
	cd ubuntu
	if [ ! -d buildroot ]; then
		git clone $SHALLOW_FLAG https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
	fi
	cd buildroot
	if [ $UID -eq 0 ]; then
		export FORCE_UNSAFE_CONFIGURE=1
	fi
	cp $ROOTDIR/configs/buildroot/lx2160acex7_defconfig configs/
	printf 'BR2_PRIMARY_SITE="%s"\n' "${BR2_PRIMARY_SITE}" >> configs/lx2160acex7_defconfig
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
		wget -c -P /tmp/ http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-arm64.tar.gz
		tar zxf /tmp/ubuntu-base-20.04.1-base-arm64.tar.gz -C /mnt
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
		chroot /mnt apt install --no-install-recommends -y systemd-sysv apt locales less wget procps openssh-server ifupdown net-tools isc-dhcp-client ntpdate lm-sensors i2c-tools psmisc less sudo htop iproute2 iputils-ping kmod network-manager iptables rng-tools apt-utils ethtool
		echo -e "root\nroot" | chroot /mnt passwd
		sed -i "s;[# ]*RuntimeWatchdogSec=.*\$;RuntimeWatchdogSec=30;g" /etc/systemd/system.conf
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
	truncate -s $ROOTFS_SIZE $IMG
	qemu-system-aarch64 -m 1G -M virt -cpu cortex-a57 -nographic -smp 1 -kernel output/images/Image -append "console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -initrd output/images/rootfs.cpio.gz -drive file=$IMG,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -no-reboot
	mv $IMG $ROOTDIR/build/ubuntu-core.ext4
fi

if [[ ! -f $ROOTDIR/build/debian-bullseye.ext4 ]] && [ "x$DISTRO" == "xdebian" ]; then
	cd $ROOTDIR/build
	mkdir -p debian
	cd debian
	if [ ! -d buildroot ]; then
		git clone $SHALLOW_FLAG https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
	fi
	cd buildroot
	if [ $UID -eq 0 ]; then
		export FORCE_UNSAFE_CONFIGURE=1
	fi
	cp $ROOTDIR/configs/buildroot/lx2160acex7_defconfig configs/
	printf 'BR2_PRIMARY_SITE="%s"\n' "${BR2_PRIMARY_SITE}" >> configs/lx2160acex7_defconfig
	make lx2160acex7_defconfig
	mkdir -p overlay/etc/init.d/
	cat > overlay/etc/init.d/S99bootstrap-debian.sh << EOF
#!/bin/sh

case "\$1" in
	start)
		resize
		mkfs.ext4 -F /dev/vda -b 4096
		mount /dev/vda /mnt
		cd /tmp
		udhcpc -i eth0
		wget http://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.123.tar.gz
		tar zxf debootstrap*.tar.gz
		cd debootstrap
		mkdir -p /usr/share/debootstrap/scripts
		mkdir -p /usr/sbin
		cp -a scripts/* /usr/share/debootstrap/scripts
		install -o root -g root -m 0644 functions /usr/share/debootstrap
		sed 's/@VERSION@/\$(VERSION)/g' debootstrap > /usr/sbin/debootstrap
		chown root:root /usr/sbin/debootstrap
		chmod 0755 /usr/sbin/debootstrap
		mkdir -p /tmp/cache
		mkdir -p /mnt/var/lib/apt
		mkdir -p /mnt/var/cache/apt
		mount -t tmpfs tmpfs /mnt/var/lib/apt/
		mount -t tmpfs tmpfs /mnt/var/cache/apt/
		debootstrap --no-check-certificate --verbose --arch arm64 --cache-dir=/tmp/cache --include=fdisk,e2fsprogs,isc-dhcp-client,ntpdate,sudo bullseye /mnt
		#debootstrap --no-check-certificate --verbose --arch arm64 --cache-dir=/tmp/cache --include=locales,less,wget,procps,openssh-server,ifupdown,net-tools,isc-dhcp-client,ntpdate,lm-sensors,i2c-tools,psmisc,sudo,htop,iproute2,iputils-ping,kmod,network-manager,iptables,rng-tools,apt-utils bullseye /mnt
		echo "nameserver 8.8.8.8" > /mnt/etc/resolv.conf
		echo "localhost" > /mnt/etc/hostname
		echo "127.0.0.1 localhost" > /mnt/etc/hosts
		echo -e "root\nroot" | chroot /mnt passwd
		sed -i "s;[# ]*RuntimeWatchdogSec=.*\$;RuntimeWatchdogSec=30;g" /etc/systemd/system.conf
		umount /mnt/var/lib/apt/
		umount /mnt/var/cache/apt/
		reboot
		;;
esac
EOF
	chmod +x overlay/etc/init.d/S99bootstrap-debian.sh
	make
	IMG=debian-bullseye.ext4.tmp
	truncate -s 350M $IMG
	qemu-system-aarch64 -m 1G -M virt -cpu cortex-a57 -nographic -smp 1 -kernel output/images/Image -append "console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -initrd output/images/rootfs.cpio.gz -drive file=$IMG,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -no-reboot
	mv $IMG $ROOTDIR/build/debian-bullseye.ext4
fi

if [[ ! -d $ROOTDIR/build/qoriq-mc-binary ]]; then
	cd $ROOTDIR/build
	git clone $SHALLOW_FLAG https://github.com/NXP/qoriq-mc-binary.git -b $RELEASE
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
	cp tools/fiptool/ddr-phy-binary/lx2160a/*.bin .
	make -j${PARALLEL} PLAT=lx2160acex7 all fip fip_ddr_sec fip_fuse pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/RCW/template.bin TRUSTED_BOARD_BOOT=1 CST_DIR=$ROOTDIR/build/cst/ GENERATE_COT=0 BOOT_MODE=${BOOT_MODE_VAR} SECURE_BOOT=yes FUSE_PROG=1 FUSE_PROV_FILE=$ROOTDIR/build/cst/fuse_scr.bin $ATF_DEBUG
else
	make -j${PARALLEL} PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/RCW/template.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=auto SECURE_BOOT=false $ATF_DEBUG
       #	DDR_PHY_DEBUG=yes DDR_DEBUG=yes # DEBUG_PHY_IO=yes
fi

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
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/freescale/fsl-lx216*.dtb $ROOTDIR/images/tmp/boot



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
    linux /boot/Image
    fdtdir /boot/
    APPEND console=ttyAMA0,115200 earlycon=pl011,mmio32,0x21c0000 default_hugepagesz=1024m hugepagesz=1024m hugepages=2 pci=pcie_bus_perf root=PARTUUID=30303030-01 rw rootwait
EOF

cp $ROOTDIR/build/$ROOTFS.ext4 $ROOTDIR/images/tmp/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:extlinux
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/extlinux/extlinux.conf $ROOTDIR/images/tmp/$ROOTFS.ext4:extlinux/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/$ROOTFS.ext4:boot
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/Image $ROOTDIR/images/tmp/$ROOTFS.ext4:boot/
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

truncate -s 420M $ROOTDIR/images/tmp/$ROOTFS.img
parted --script $ROOTDIR/images/tmp/$ROOTFS.img mklabel msdos mkpart primary 64MiB 417MiB
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/$ROOTFS.ext4 of=$ROOTDIR/images/tmp/$ROOTFS.img bs=1M seek=64 conv=notrunc

echo "Assembling Boot Image"
cd $ROOTDIR/
IMG=lx2160acex7_${SPEED}_${SERDES}-${REPO_PREFIX}.img
rm -rf $ROOTDIR/images/${IMG}
truncate -s 528M $ROOTDIR/images/${IMG}
#dd if=/dev/zero of=$ROOTDIR/images/${IMG} bs=1M count=1
parted --script $ROOTDIR/images/${IMG} mklabel msdos mkpart primary 64MiB 527MiB
truncate -s 463M $ROOTDIR/images/tmp/boot.part
mkfs.ext4 -b 4096 -F $ROOTDIR/images/tmp/boot.part
\rm -rf $ROOTDIR/images/tmp/xspi_header.img
truncate -s 128K $ROOTDIR/images/tmp/xspi_header.img
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/${BL2}.pbl of=$ROOTDIR/images/tmp/xspi_header.img bs=512 conv=notrunc
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/xspi_header.img $ROOTDIR/images/tmp/boot.part:/

# PFE firmware at 0x100

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/atf/build/lx2160acex7/${ATF_BUILD}/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

# DDR PHY FIP at 0x4000
if [ "x$SECURE" == "xtrue" ]; then
	dd if=$ROOTDIR/build/atf/fip_ddr_sec.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
else
	dd if=$ROOTDIR/build/atf/tools/fiptool/fip_ddr_all.bin of=images/${IMG} bs=512 seek=16384 conv=notrunc
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
		dd if=$ROOTDIR/build/qoriq-mc-binary/lx216xa/${MC} of=images/${IMG} bs=512 seek=20480 conv=notrunc
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
