# use debian base
FROM debian:buster-slim

# apt proxy (optional)
ARG APTPROXY=
RUN test -n "$APTPROXY" && printf 'Acquire::http { Proxy "%s"; }\n' $APTPROXY | tee -a /etc/apt/apt.conf.d/proxy || true

# update
RUN set -e; \
	apt-get update; \
	apt-get -y upgrade; \
	:

RUN apt-get update ; apt-get -y install build-essential wget make p7zip p7zip-full \
        device-tree-compiler acpica-tools xz-utils sudo gcc libssl-dev python2 \
        bison flex u-boot-tools git bc fuseext2 e2tools multistrap \
        qemu-system-arm g++ cpio python unzip rsync dosfstools tar pandoc \
        python3 meson ninja-build squashfs-tools parted mtools kmod

# build environment
WORKDIR /work
COPY shflags /
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
