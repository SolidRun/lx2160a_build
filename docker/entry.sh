#!/bin/sh -e
# Copyright 2018-2019 Josua Mayer <josua@solid-run.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# 

if [ $# -ne 2 ]; then
	echo "Error: Missing arguments uid and gid!"
	echo "Maybe you forgot to pass <uid> <gid> to docker run?"
	exit 1
fi

_UID=$1
_GID=$2

# create build user (and group if it does not exist)
groupadd -g $_GID build 2>/dev/null || true
useradd -s /bin/bash -m -u $_UID -g $_GID build

# passwordless sudo for build user
adduser build sudo
echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# preconfigure git identity
sudo -u build git config --global user.name "LX2160A Toolchain Container"
sudo -u build git config --global user.email "support@solid-run.com"

cd /work
# now run the build script as the build user
sudo -u build -E ./runme.sh
