# use debian base
FROM debian:buster-slim

# update
RUN set -e; \
	apt-get update; \
	apt-get -y upgrade; \
	:

RUN apt-get -y install wget make tar p7zip-full squashfs-tools vim \
	e2fsprogs parted dosfstools acpica-tools mtools \
	device-tree-compiler xz-utils sudo gcc libssl-dev python2 \
	bison flex u-boot-tools git bc fuseext2 e2tools multistrap \
	qemu-user-static g++ cpio python python3 unzip rsync

# build environment
WORKDIR /work
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
