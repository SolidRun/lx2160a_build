# use debian base
FROM python:slim-buster

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

RUN apt-get update ; apt-get -y install --no-install-recommends acpica-tools bc bison build-essential ca-certificates cpio debian-archive-keyring debootstrap device-tree-compiler dosfstools e2tools fakeroot file flex fuseext2 g++ gcc git kmod libncurses-dev libssl-dev libyaml-dev make meson mtools multistrap ninja-build p7zip p7zip-full pandoc parted pkg-config python python2 python3 qemu-system-arm rsync squashfs-tools sudo tar u-boot-tools unzip wget xz-utils yamllint

RUN set -e; \
	apt-get -y install --no-install-recommends libpython3-dev python3-pip python3-setuptools python3-wheel swig; \
	pip3 install importlib-metadata; \
	pip3 install dtschema; \
	:

# build environment
WORKDIR /work
COPY shflags /
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
