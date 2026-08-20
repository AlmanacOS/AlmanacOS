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

# installl ramalama    
dnf5 -y install ramalama

# add lemonade via copr:
dnf5 -y copr enable abn/lemonade
dnf5 -y install lemonade
# disable lemonade copr so it is not enabled on the image
dnf5 -y copr disable abn/lemonade

# AMD-specific: install native fastflowlm and hrx
dnf5 -y copr enable abn/amd-npu
dnf5 -y install fastflowlm hrx
dnf5 -y copy disable abn/amd-npu

# AlmanacOS RPMs via copr
dnf5 -y copr enable clemperorpenguin/AlmanacOS
dnf5 -y install amdgpu_top almanac-model-fetch
dnf5 -y copr disable clemperorpenguin/AlmanacOS

### Agent sandbox
#
# crun-krun is nothing but a /usr/bin/krun symlink to crun plus a man page — the
# krun handler is already compiled into stock crun. What is actually missing
# from the base image is libkrun, the shared library that handler dlopen()s at
# runtime. Without it podman fails deep inside crun with a message that never
# mentions krun, so both are installed together and never separately.
#
# libkrun drags in libkrunfw (the guest kernel), pipewire, and virglrenderer.
# That is real weight for an image with no GPU passthrough yet; it is the price
# of the packaged library.
#
# jq is what /usr/libexec/almanac-agentbox reads the agent registry with.
dnf5 install -y crun-krun libkrun jq

# One registry, two consumers. agent_image/agents.json is copied into the guest
# rootfs by agent_image/Containerfile and onto the host here, so `agentbox
# --list` and what the VM can actually run are the same list by construction.
install -D -m 0644 /ctx/agent_image/agents.json /usr/share/almanac/agents.json

# microsandbox prebuilt runtime (see script header for why it is not an RPM).
/ctx/microsandbox.sh

# Merge the agent image's signature requirement into the base image's container
# policy rather than replacing the file. `default: reject` or a wholesale
# overwrite would break every unsigned pull on the system — Flatpak runtimes,
# toolbox images, the base image itself.
python3 - <<'EOF'
import json
import os

POLICY = "/etc/containers/policy.json"
FRAGMENT = "/usr/share/almanac/agent-policy.json"

with open(FRAGMENT) as f:
    fragment = json.load(f)

if os.path.exists(POLICY):
    with open(POLICY) as f:
        policy = json.load(f)
else:
    policy = {"default": [{"type": "insecureAcceptAnything"}]}

transports = policy.setdefault("transports", {})
for transport, scopes in fragment["transports"].items():
    transports.setdefault(transport, {}).update(scopes)

with open(POLICY, "w") as f:
    json.dump(policy, f, indent=4)
    f.write("\n")

print(f"merged agent signature policy into {POLICY}")
EOF

#### Example for enabling a System Unit File
systemctl enable podman.socket

systemctl enable lemond

### Homebrew (from ghcr.io/ublue-os/brew — same mechanism Bluefin/Bazzite use)
# brew-setup.service extracts /usr/share/homebrew.tar.zst to /home/linuxbrew on
# first boot, guarded by /etc/.linuxbrew. The preset file ships in system_files.
systemctl preset brew-setup.service
systemctl preset brew-update.timer
systemctl preset brew-upgrade.timer

# Make sure just scripts are executable
chmod +x /usr/libexec/almanac-memory
chmod +x /usr/libexec/almanac-models
chmod +x /usr/libexec/almanac-agentbox
chmod +x /usr/libexec/almanac-agent-proxy
chmod +x /usr/libexec/almanac-agent-selftest

# `agentbox` is the name users type. It is deliberately not `claude`: a wrapper
# that shadows the real binary on PATH means nobody can tell which one they are
# running, and the sandbox has to be an obvious choice to be a meaningful one.
ln -sf ../libexec/almanac-agentbox /usr/bin/agentbox
