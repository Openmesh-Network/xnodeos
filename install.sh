#!/usr/bin/env bash

set -e # Stop on error

# Download and extract kexec archive
if [[ $VERSION ]]; then
    URL="https://github.com/Openmesh-Network/xnodeos/releases/download/${VERSION}/xnodeos-kexec-installer-$(uname -m)-linux.tar.gz"
else
    URL="https://github.com/Openmesh-Network/xnodeos/releases/latest/download/xnodeos-kexec-installer-$(uname -m)-linux.tar.gz"
    export VERSION="latest"
fi
curl -L "$URL" | tar -xzf- -C /root

# Boot into kexec
/root/xnodeos/install