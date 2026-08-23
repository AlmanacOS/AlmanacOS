# AlmanacOS

**PRE-ALPHA not for production**

AlmanacOS is a bootc desktop image for running language models on hardware you
own - including hardware that never touches a network. Fedora Kinoite
underneath, so it is a KDE desktop that updates atomically and rolls back when
an update goes wrong.

Working offline is the constraint the rest of the design falls out of, not a
feature bolted on the side. Models arrive on a USB drive and are checked against
a key you carried here separately; the one component that is not an RPM is
pinned by digest; the live ISO installs out of container storage on the disc,
because on a machine with no network a registry transport would mean the ISO
cannot install the OS it is an ISO of.

**Status:** the image builds and publishes to `ghcr.io/almanacos/almanacos`,
cosign-signed by CI. Two things are not done - the live ISO is wired up end to
end and **has never been booted**, and signature verification is **not
enforced** on `bootc upgrade`. Both are on the roadmap.

## Install

Rebase a machine already running a bootc image (Kinoite, Bluefin,
Fedora Atomic). This is the tested path:

```bash
sudo bootc switch ghcr.io/almanacos/almanacos:latest
systemctl reboot
```

There is also a live ISO - `just build-iso`, or the `Build disk images`
workflow. Read [docs/installer/SETUP.md](docs/installer/SETUP.md) first,
including the part where it says nobody has booted one yet.

## What's in it

- **Lemonade** (`lemond`, enabled at boot) and **ramalama**, for serving models.
- **microsandbox** (`msb`), for running untrusted code in a real microVM.
- **`ujust almanac-*`** recipes for offline model import and APU memory tuning.
- **Homebrew**, unpacked on first boot, plus `podman.socket`, `tmux`, `jq`,
  `amdgpu_top`.
- **Bazaar** as the app store in place of Discover, which is removed. Flathub is
  preconfigured system-wide.
- Flatpaks pulled on first boot, network permitting: Bazaar, Alpaca, Haruna,
  Kontainer, Flatseal, Mission Center, Upscayl. Fedora's Flatpak remotes - and
  anything already installed from them - are removed on first boot, from both
  the system and per-user installations.

## Running a model

`lemond` starts at boot and serves an OpenAI-compatible API on port 13305.

```bash
lemonade list                     # what exists, and what is downloaded
lemonade pull Qwen3-0.6B-GGUF
lemonade chat Qwen3-0.6B-GGUF     # or point anything at localhost:13305/v1
```

`lemonade run` opens the web UI; Alpaca is preinstalled if you would rather have
a desktop client.

## Sandboxing untrusted code

`msb` runs code in a hardware-virtualised microVM, not a container - separate
kernel, so container escape is not the threat model. Useful for anything a model
wrote and you have not read.

```bash
msb run python -- python3 -c "print('hello from a microVM')"

msb create --name app python      # a persistent one
msb exec app -- python -c "import this"
msb stop app && msb rm app
```

It ships as a pinned prebuilt bundle rather than an RPM, installed beside its own
forked `libkrunfw` so that fork can never shadow a packaged one.
[`build_files/microsandbox.sh`](build_files/microsandbox.sh) explains why, and is
worth reading before changing any of it.

## Importing models with no network

The fetching half (`amf`) runs on a networked machine and writes signed bundles
to a drive. This half re-checks every claim those bundles make, offline.

```bash
ujust almanac-trust-model-key /path/to/amf.pub   # once, ever
ujust almanac-list-models                        # what is on the drive
ujust almanac-verify-models                      # re-check it, write nothing
ujust almanac-import-models                      # verify, then install
```

Carry `amf.pub` separately from the models. A key taken off the same drive as the
bundles vouches for nothing - whoever wrote the bundles could have written the
key. Full procedure in [OPERATING.md](docs/model-import/OPERATING.md); the
reasoning in [DESIGN.md](docs/model-import/DESIGN.md).

## Memory tuning on unified-memory APUs

On an APU the iGPU is the primary compute device and system RAM *is* VRAM, so the
kernel's default TTM cap of roughly half of RAM is in the way.

```bash
ujust almanac-show-memory
ujust almanac-tune-memory 75
ujust almanac-reset-memory
```

It refuses to touch a system with a discrete GPU, on purpose - there the cap is a
guard rail against the OOM killer. Reasoning in the header of
[`almanac-memory`](system_files/usr/libexec/almanac-memory).

## Building it yourself

`just build` builds the image, `just build-iso` the live ISO, `just check` lints
the build context. `just verify-microsandbox` checks the pin still matches the
release, and `just bump-microsandbox <version>` only writes a new digest after
`gh release verify-asset` passes - neither trusts a download. This started from
the Universal Blue `image-template`, whose instructions are at
[docs/ublue/README.md](docs/ublue/README.md).

## Roadmap

**Boot the ISO.** It is built and it is untested, and those are two different
things.

**Enforce signature verification on upgrade.** The key already ships at
`/etc/pki/containers/almanacos.pub`; what is missing is
`ostree-image-signed:docker://` in the kickstart and a `sigstoreSigned` entry in
`policy.json`. Deferred rather than forgotten - a policy that rejects the base
image breaks `bootc upgrade` on every machine already carrying that policy, and
recovering means a rollback. Pending a dedicated test machine.

**An agent layer on top of `msb`.** The bespoke `almanac-agent` sandbox image was
removed in 7097881 - a second image, a second CI pipeline and ~3,000 lines, for
isolation `msb` already provides. Whatever replaces it should drive stock
microsandbox.

**A headless image.** All of the above without the desktop, for servers and for
machines that have no business running KDE.

## Licence

Apache 2.0. See [LICENSE](LICENSE).
