# use debian base
FROM debian:buster-slim

# apt proxy (optional)
ARG APTPROXY=
RUN test -n "$APTPROXY" && printf 'Acquire::http { Proxy "%s"; }\n' $APTPROXY | tee -a /etc/apt/apt.conf.d/proxy || true

# prevent dpkg interactive dialogues
ENV DEBIAN_FRONTEND=noninteractive

# update
RUN set -e; \
	apt-get update; \
	apt-get -y upgrade; \
	:

RUN apt-get update ; apt-get -y install --no-install-recommends acpica-tools bc bison build-essential ca-certificates cpio debian-archive-keyring debootstrap device-tree-compiler dosfstools e2tools fakeroot flex fuseext2 g++ gcc git kmod libssl-dev make meson mtools multistrap ninja-build p7zip p7zip-full pandoc parted python python2 python3 qemu-system-arm rsync squashfs-tools sudo tar u-boot-tools unzip wget xz-utils

# build environment
WORKDIR /work
COPY shflags /
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
