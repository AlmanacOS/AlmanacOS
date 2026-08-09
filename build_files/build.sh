#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# add lemonade via copr:
dnf5 -y copr enable abn/lemonade
dnf5 -y install lemonade
# disable lemonade copr so it is not enabled on the image
dnf5 -y copr disable abn/lemonade

dnf5 -y copr enable clemperorpenguin/AlmanacOS
dnf5 -y install amdgpu_top
dnf5 -y copr disable clemperorpenguin/AlmanacOS

#### Example for enabling a System Unit File
systemctl enable podman.socket

systemctl enable lemond

# Make sure just scripts are executable
chmod +x /usr/libexec/almanac-memory
chmod +x /usr/libexec/almanac-models
