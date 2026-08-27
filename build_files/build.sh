#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# ramalama, as an RPM and not from Homebrew. Bluefin ships it in
# ai-tools.Brewfile; AlmanacOS deliberately does not, because a machine that
# never sees a network still needs both serving paths present at first boot.
# The consequence is that `brew install ramalama` must stay out of
# /usr/share/almanac/homebrew/ai-local.Brewfile — Homebrew's prefix precedes
# /usr/bin on PATH, so a brew copy would silently shadow this one.
dnf5 -y install ramalama

# add lemonade via copr:
dnf5 -y copr enable clemperorpenguin/lemonade
dnf5 -y install lemonade
# disable lemonade copr so it is not enabled on the image
dnf5 -y copr disable clemperorpenguin/lemonade

# AMD-specific: install native fastflowlm and hrx - disabled for now
# dnf5 -y copr enable abn/amd-npu
# dnf5 -y install fastflowlm hrx
# dnf5 -y copy disable abn/amd-npu

# AlmanacOS RPMs via copr
dnf5 -y copr enable clemperorpenguin/AlmanacOS
dnf5 -y install amdgpu_top almanac-model-fetch
dnf5 -y copr disable clemperorpenguin/AlmanacOS

# jq, for shell tooling that reads JSON.
dnf5 install -y jq

# gum, for the `ujust devmode` and `ujust ai` menus. /usr/bin/ugum from
# ublue-os-just is an fzf shim covering only choose and confirm, not style or
# spin, so it is not a substitute here.
dnf5 install -y gum

### Bazaar replaces Discover as the app store.
# Discover is inherited from kinoite-main (which only excludes the rpm-ostree
# backend), so it has to be removed here or the image ships two app stores.
# Query first: the exact subpackage set moves around between Fedora releases,
# and `dnf5 remove` on an absent package is fatal under `set -e`.
mapfile -t discover_pkgs < <(rpm -qa --queryformat '%{NAME}\n' 'plasma-discover*')
if [[ ${#discover_pkgs[@]} -gt 0 ]]; then
    dnf5 -y remove "${discover_pkgs[@]}"
fi

# Fedora's Flatpak remote definitions, if the base still carries them.
if rpm -q fedora-flatpak-repo > /dev/null 2>&1; then
    dnf5 -y remove fedora-flatpak-repo
fi

# microsandbox prebuilt runtime (see script header for why it is not an RPM).
/ctx/microsandbox.sh

#### Example for enabling a System Unit File
systemctl enable podman.socket

systemctl enable lemond

systemctl enable flatpak-preinstall.service
systemctl enable flatpak-nuke-fedora.service

# Bazaar's background service and the per-user half of the Fedora nuke. A system
# unit cannot reach ~/.local/share/flatpak, hence the second one.
systemctl --global enable bazaar.service
systemctl --global enable almanac-flatpak-nuke-fedora.service

### Homebrew (from ghcr.io/ublue-os/brew — same mechanism Bluefin/Bazzite use)
# brew-setup.service extracts /usr/share/homebrew.tar.zst to /home/linuxbrew on
# first boot, guarded by /etc/.linuxbrew. The preset file ships in system_files.
systemctl preset brew-setup.service
systemctl preset brew-update.timer
systemctl preset brew-upgrade.timer

# Make sure just scripts are executable
chmod +x /usr/libexec/almanac-memory
chmod +x /usr/libexec/almanac-models
chmod +x /usr/libexec/almanac-flatpak-nuke-fedora
chmod +x /usr/libexec/almanac-devmode
chmod +x /usr/libexec/almanac-ai
chmod +x /usr/libexec/almanac-sandbox-exec

# The ujust manifest is the only thing that makes any almanac recipe reachable:
# ublue-os-just bakes a fixed import list into /usr/share/ublue-os/justfile and
# leaves exactly one optional slot, 60-custom.just, which we fill with imports.
# Those imports are `import?` so `just check` can parse the file in CI, where
# these paths do not exist — which means a typo would fail silently at runtime
# instead of loudly here. Assert it now rather than shipping dead recipes again.
while read -r recipe; do
    [[ -e "$recipe" ]] || {
        echo "60-custom.just imports ${recipe}, which is not in the image" >&2
        exit 1
    }
done < <(grep -oP 'import\? "\K[^"]+' /usr/share/ublue-os/just/60-custom.just)
