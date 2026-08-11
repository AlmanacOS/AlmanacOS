#!/usr/bin/bash
# Turn the AlmanacOS image into a live ISO rootfs.
#
# Everything here runs at container build time and only affects the live
# environment. The system Anaconda installs comes from the embedded payload
# image, which none of this touches.
#
# The structure follows ublue-os/titanoboa's bazzite example, which is the
# working reference for this path. Where it does something AlmanacOS does not
# need — akmod kernel swapping for secure boot, flatpak preloading, Steam
# removal — it is left out rather than carried along.

set -exo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The image the installer lays down. The same reference the Containerfile built
# FROM, passed in rather than written again: the payload and the live rootfs
# being different builds is a bug that would only show up after an install.
readonly PAYLOAD_IMAGE="${BASE_IMAGE:?BASE_IMAGE must be passed in from the Containerfile}"

# /root is a symlink into /var on an ostree system, and the target does not
# exist in a container build. dracut and podman both want to write there.
mkdir -p "$(realpath /root)"

# ---------------------------------------------------------------------------
# The install payload
#
# Pulled into the live rootfs's own container storage, so the ISO carries the
# system it installs and Anaconda never touches the network. This is the whole
# reason an AlmanacOS ISO is worth building: the machines this installs onto are
# expected not to have a network, and an installer that needs one to lay down
# the OS would contradict the OS.
#
# It also roughly doubles the ISO. That is the trade and it is deliberate.
podman pull "$PAYLOAD_IMAGE"

# ---------------------------------------------------------------------------
# Live boot
#
# dracut-live provides the dmsquash-live module, which is what mounts the
# squashfs the ISO boots from. Without regenerating the initramfs with it, the
# live entry in iso.yaml drops to a dracut shell.
dnf install -y dracut-live

kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')

# DRACUT_NO_XATTR: the build container cannot set the security.* xattrs dracut
# would otherwise write. autooverlay sizes the writable overlay from RAM rather
# than a fixed 512M, which matters because installing writes into it.
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# livesys does the live-session setup at boot: the liveuser account, autologin,
# and the desktop tweaks for the named session. AlmanacOS is Kinoite-derived,
# so the session is kde.
dnf install -y livesys-scripts
sed -i "s/^livesys_session=.*/livesys_session=kde/" /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# ---------------------------------------------------------------------------
# Anaconda
#
# anaconda-live is the live-media variant, started by `liveinst` from inside the
# running desktop rather than by a boot menu entry. On Fedora 43 media that
# launches the Web UI.
#
# firefox is not optional: the Web UI is a web page and something in the live
# session has to render it. libblockdev's btrfs/lvm/dm plugins are what
# Anaconda's storage module uses to offer those layouts at all.
dnf install -y --allowerasing \
    anaconda-live \
    firefox \
    libblockdev-{btrfs,lvm,dm}

# The Web UI writes here during the install and does not create it.
mkdir -p /var/lib/rpm-state

install -Dm 0644 "$SCRIPT_DIR/almanacos.conf" /etc/anaconda/profile.d/almanacos.conf

# Appended, not overwritten: anaconda-live ships this file with content of its
# own and replacing it wholesale discards whatever the product needs.
#
# @PAYLOAD_IMAGE@ is substituted rather than written into the file so the
# reference has exactly one source, the Containerfile's BASE_IMAGE.
sed "s|@PAYLOAD_IMAGE@|${PAYLOAD_IMAGE}|g" "$SCRIPT_DIR/interactive-defaults.ks" \
    >>/usr/share/anaconda/interactive-defaults.ks

# `grep -q ... && exit` would abort the script under errexit on the *success*
# path, since a failed grep makes the whole && list return non-zero.
if grep -q '@PAYLOAD_IMAGE@' /usr/share/anaconda/interactive-defaults.ks; then
    echo "payload reference was not substituted" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# The ISO itself

# Titanoboa reads the boot menu from here.
install -Dm 0644 "$SCRIPT_DIR/iso.yaml" /usr/lib/bootc-image-builder/iso.yaml

# gcdx64.efi, which the ISO's EFI boot path needs and the normal image does not
# carry.
dnf install -y grub2-efi-x64-cdboot

# The EFI binaries are read from /boot/efi/EFI/$VENDOR, but the packages install
# them under /usr/lib/efi.
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/

# Needed inside the container that assembles the ISO.
dnf install -y xorriso isomd5sum

# ---------------------------------------------------------------------------
# Live session behaviour

# A live session has no configured timezone and no way to ask before the
# installer runs.
rm -f /etc/localtime
systemd-firstboot --timezone UTC

# On a booted live ISO / is an overlayfs whose upperdir lives under /run, a
# tmpfs sized for /run rather than for unpacking an OS. ostree needs real space
# in /var/tmp during the install, so give it its own larger tmpfs.
rm -rf /var/tmp || :
mkdir -p /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on the live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%,nr_inodes=1m

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

# Services that make no sense before the system is installed. lemond is the
# expensive one: it scans for models and loads one, on a machine that is running
# entirely out of RAM and has no imported models to find.
for unit in \
    lemond.service \
    podman-auto-update.timer \
    rpm-ostreed-automatic.timer \
    uupd.timer; do
    systemctl disable "$unit" || :
done

dnf clean all
