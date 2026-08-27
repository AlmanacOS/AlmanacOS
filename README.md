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
- **Homebrew**, unpacked on first boot, plus `podman.socket`, `gum`, `jq`,
  `amdgpu_top`.
- **`ujust devmode`** and **`ujust ai`**, which install developer tooling and
  terminal AI agents into your home directory on request. Neither is in the
  image; both need a network.
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

## Developer tooling and AI agents

Neither ships in the image. `ujust devmode` and `ujust ai` are installers: they
fetch from Homebrew and Flathub at the moment you run them, into `$HOME` or the
system Flatpak installation, and nothing they install survives a `bootc switch`
away. That is the trade. The base image stays small for the majority of machines
that will never open an IDE, and the tooling is not pinned to our build cadence.

```bash
ujust devmode            # containers, VMs, IDEs, editors, Kubernetes
ujust devmode-preflight  # are the install hosts reachable?
ujust dx-group           # just the groups, for a second user account
ujust ai                 # terminal AI agents
```

Both refuse to start on a machine with no network, and say what they would have
downloaded instead of failing inside Homebrew. This is the one part of AlmanacOS
that needs the internet, and it is meant to be obvious about it.

Picking Docker installs the CLI only. There is no Docker daemon here and there
will not be one: `DOCKER_HOST` is pointed at the rootless Podman socket that is
already enabled, which is why nothing asks to add you to a `docker` group.

### Pointing agents at a local model

Most terminal agents speak the OpenAI API and will talk to anything that
implements it, including both servers on this image.

```bash
ujust almanac-ai-backend             # auto: whichever is answering
ujust almanac-ai-backend lemonade    # localhost:13305
ujust almanac-ai-backend ramalama    # localhost:8080
```

This writes `OPENAI_BASE_URL` into `~/.config/environment.d`, plus config for
`aichat` and `llm`, which do not read it. It works offline — it changes where
tools point, and downloads nothing. Environment changes apply at your next login.

The developer and AI tooling is adapted from
[Bluefin](https://projectbluefin.io), Apache-2.0 like AlmanacOS; the files that
carry ported code cite the upstream path and commit in their headers.

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

`almanac-sandbox-exec` wraps this for agents: point a coding agent's shell hook
at it and the code it writes runs in a microVM instead of your session. The
sandbox is ephemeral and your working directory is not mounted, which is the
point rather than an oversight.

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
