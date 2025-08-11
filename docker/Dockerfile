FROM python:slim-bookworm

# enable backports
RUN printf "deb http://deb.debian.org/debian bookworm-backports main\n" >> /etc/apt/sources.list

# retry at least 3 times to succeed on sketchy connections
RUN printf 'Acquire::http { Proxy "%s"; };\n' $APTPROXY | tee -a /etc/apt/apt.conf.d/proxy

# apt proxy (optional)
ARG APTPROXY=
RUN printf 'Acquire::Retries 3;\n' | tee -a /etc/apt/apt.conf.d/retry || true

# prevent dpkg interactive dialogues
ENV DEBIAN_FRONTEND=noninteractive

# install updates
RUN set -e; \
	apt-get update; \
	apt-get upgrade -y; \
	:

# Install packages
RUN set -e; \
	apt-get update; \
	apt-get --no-install-recommends -y install \
		acpica-tools bc bison build-essential ca-certificates cmake cpio debian-archive-keyring debootstrap device-tree-compiler dosfstools e2tools fakeroot fdisk file flex git kmod libncurses-dev libssl-dev libyaml-dev lzop make meson mtools ninja-build p7zip p7zip-full pandoc parted pkg-config qemu-system-arm rsync sudo tar u-boot-tools unzip wget xz-utils yamllint; \
	dpkg-architecture --is arm64 || apt-get --no-install-recommends -y install crossbuild-essential-arm64; \
	:

RUN set -e; \
	apt-get -y install --no-install-recommends libpython3-dev python3-pip python3-setuptools python3-wheel swig; \
	pip3 install importlib-metadata; \
	pip3 install pylibfdt==1.7.0.post1 dtschema; \
	pip3 install cryptography; \
	pip3 install pyelftools; \
	:

RUN apt-get install -y python3-pyelftools

# build environment
WORKDIR /work
COPY shflags /
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
