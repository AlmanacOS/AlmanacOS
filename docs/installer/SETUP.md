# The AlmanacOS live ISO and installer

**Status:** wired up end to end, **never booted.** The first ISO is the first
test.
**Built from:** `iso_image/`
**Build it:** `just build-iso` (locally) or the `Build disk images` workflow.

## What it is

A live ISO of AlmanacOS itself. It boots the real KDE desktop off the disc, and
Anaconda's Web UI is launched from inside that session — the same shape as
Bazzite's and Bluefin's ISOs, built with the same tool
([titanoboa](https://github.com/ublue-os/titanoboa)).

```
iso_image/
├── Containerfile                 FROM the published AlmanacOS image
└── src/
    ├── build.sh                  adds the live session, Anaconda, the payload
    ├── iso.yaml                  the ISO's boot menu
    ├── almanacos.conf            Anaconda profile
    └── interactive-defaults.ks   what gets installed, and where it updates from
```

Titanoboa takes that container and produces the ISO. There is no build-side
config file: the contract is that everything the ISO needs — boot menu, kernel,
initramfs, EFI binaries — is *inside* the image.

## A correction

An earlier version of this document, and of the code it described, asserted that
the Anaconda Web UI is enabled by the `inst.webui` kernel argument "and by
nothing else — there is no kickstart directive and no anaconda.conf setting."

That is true of a traditional non-live `boot.iso`, which is what that version
built. It is not true here and it was wrong as a general claim. On live media
the installer is `anaconda-live`, started by `liveinst` from the desktop
session, and the Web UI is what that starts on Fedora 43 media — no kernel
argument is involved. Bazzite's live ISO passes no `inst.*` arguments at all and
still gets the Web UI, and then tunes it through `hidden_webui_pages` in its
Anaconda profile, which is only meaningful if the Web UI is already running.

`inst.webui` is also not in Anaconda's documented boot options; it appears in
the lorax template patch upstream uses to build its Web UI `boot.iso`. Treating
it as *the* mechanism was an over-generalisation from one path.

## How the pieces fit

**The live session.** `build.sh` installs `dracut-live` and regenerates the
initramfs with `dmsquash-live`, which is what mounts the squashfs the ISO boots
from. `livesys-scripts` does the boot-time live setup — the `liveuser` account,
autologin, desktop tweaks — configured for the `kde` session, AlmanacOS being
Kinoite-derived.

**The installer.** `anaconda-live`, plus `firefox` (the Web UI is a web page and
something has to render it) and libblockdev's btrfs/lvm/dm plugins (without them
Anaconda's storage module cannot offer those layouts). `/var/lib/rpm-state` is
created because the Web UI writes there and does not create it.

**The profile.** `almanacos.conf` is selected by `inst.profile=almanacos` on the
boot entry, not by detection. Detection matches on os-release, and AlmanacOS
inherits `os_id=fedora` / `variant_id=kinoite` from ublue's kinoite-main — which
is exactly what upstream's `fedora-kinoite` profile detects on. Without the
explicit argument that profile wins and ours is never read.

It is nearly empty on purpose. It sets `profile_id` and inherits
`fedora-kinoite`, and nothing else. Everything inherited — partitioning,
`webui_web_engine=firefox`, the KDE defaults — is already right for a Kinoite
derivative, and overriding it before anyone has installed from this ISO would be
guessing. Partitioning for the model store under `/var` is the obvious first
thing to revisit once there is real experience.

## The payload, and why the ISO is large

`build.sh` runs `podman pull` at image build time, so the ISO carries the
AlmanacOS image it installs. `interactive-defaults.ks` then installs it with
`--transport=containers-storage`: the install reads from the disc and never
opens a socket.

This is the point. AlmanacOS is built for machines with no network; an ISO that
needed one to lay the OS down would contradict the OS it lays down. It also
roughly doubles the ISO, since the payload sits alongside a live rootfs that is
already that image plus a desktop session. That trade is deliberate, and it is
worth measuring the result before deciding where these get published — GitHub
artifact limits are a real constraint at this size.

**The published image has to be public.** That `podman pull` runs *inside* a
container build, where the host's registry credentials are not available and
cannot easily be made available. `sudo podman login` on the runner covers the
`FROM`, but not the pull nested inside it. GHCR packages are private when first
published, so a package that has never been made public will fail this step —
and it fails deep into the build, after the base image has already been pulled.

**The origin rewrite is not optional.** Installing from container storage makes
ostree record *that* as the deployment's origin, so a freshly installed machine
believes its upstream is a container store that only existed on the ISO, and
`bootc upgrade` has nowhere to look. A `%post` rewrites it to the registry.

That reference is left **unverified**, which is the same posture the system has
today and is not the right long-term answer — these images are cosign-signed by
CI and the public key already ships at `/etc/pki/containers/almanacos.pub`.
Turning it on is two changes: `ostree-image-signed:docker://` in the kickstart,
and a `sigstoreSigned` entry for this repository merged into
`/etc/containers/policy.json` by `build_files/build.sh`. It is deliberately
left out here: a policy that rejects the
base image breaks `bootc upgrade` on every machine that has already deployed the
image *carrying that policy*, and recovering means a rollback. Worth doing on
purpose against a test machine, not as a side effect of wiring up ISO builds.

## Building it

```bash
just build-iso
```

That builds `iso_image/` (with `--cap-add sys_admin --security-opt
label=disable --squash`, all three required — `build.sh` runs podman inside the
build and regenerates the initramfs), loads it into root's container storage,
and runs titanoboa. The ISO lands in `output/`.

`just run-vm-iso` boots the result in QEMU.

**There is no `rebuild-iso`, on purpose.** The live image is built `FROM` the
*published* base image, and `build.sh` embeds the payload by pulling that same
published reference — so a locally rebuilt base image reaches neither. Testing
an OS change in an ISO means publishing the OS image first. ublue's own images
work the same way; it is a property of the path, not an oversight.

## CI

`.github/workflows/build-disk.yml`, run by hand (`workflow_dispatch`) with a
platform and an S3 toggle, and on pull requests that touch `disk_config/`,
`iso_image/`, or the workflow itself.

Two jobs, because there is no longer one tool that does both:

| Job | Builder | Output |
| --- | --- | --- |
| `disk` | Bootc Image Builder + `disk_config/disk.toml` | qcow2 |
| `iso` | `just build-iso-image` → `ublue-os/titanoboa@main` | live ISO + checksum |

The ISO job is amd64-only: the live image embeds a payload built for x86_64, and
titanoboa's grub2 handling wants i386-pc modules. An arm64 ISO needs its own
payload first.

The live image is built with `sudo` so it lands in **root's** container storage
— titanoboa reads the rootfs through `sudo podman run --mount type=image`, which
resolves against root's storage, not the runner user's.

Following the README's *Setting Up ISO Builds*:

1. **"Modify `disk_config/iso.toml` to point to your custom container image."**
   No longer applicable — that file is for BIB's `anaconda-iso` type, which no
   longer exists. `disk_config/iso-gnome.toml` and `iso-kde.toml` have been
   deleted for the same reason. The equivalent is the `BASE_IMAGE` build
   argument in `iso_image/Containerfile`, which is the single source for both
   the `FROM` and the payload — `build.sh` and `interactive-defaults.ks` get it
   passed in rather than naming it again. `just` derives it from
   `REPO_ORGANIZATION`; CI passes its own `IMAGE_REGISTRY`.
2. **"Edit `IMAGE_REGISTRY`, `IMAGE_NAME` and `DEFAULT_TAG`."** Done — they are
   derived from the repository and lowercased, matching `build.yml`.
3. **S3 secrets.** Not done, and yours to add if you want uploads:
   `S3_PROVIDER`, `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`,
   `S3_REGION`, `S3_ENDPOINT`. Without them, leave `upload-to-s3` off and the
   artifacts attach to the job.

## What is unverified

Everything, in the sense that matters: no ISO has been built from this and
nothing has been booted. Specifically worth watching on the first run —

- **Whether the Web UI actually comes up.** This mirrors Bazzite's working
  configuration, but "mirrors a working configuration" is not "works".
- **`inst.profile=almanacos`.** The argument is documented, and Anaconda reads
  `/proc/cmdline` however it was started, but Bazzite reaches its profile by
  detection rather than by this route.
- **Disabled units.** `build.sh` disables `lemond` and the update timers for the
  live session. If any of those unit names is wrong the loop swallows it —
  `systemctl disable` failures are tolerated so a renamed unit does not fail the
  build.
- **The EFI copy.** Bazzite additionally copies `grubx64.efi` over
  `EFI/BOOT/fbx64.efi` with a note that it may break the bootloader. That is not
  done here, because a workaround nobody can explain is worse than a bug that
  has not happened yet. If UEFI boot fails, that is the first thing to try.
- **ISO size and artifact limits**, per above.
