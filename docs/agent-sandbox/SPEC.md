# AlmanacOS Agent Sandbox — microVM Isolation Spec

**Status:** draft (rev 5)
**Target:** AlmanacOS (ublue base-main derived, Fedora Atomic / bootc)
**Host kernel assumption:** stock Fedora/ublue
**Isolation mechanism:** podman + `krun` OCI runtime (libkrun microVMs)
**Author:** Clem / Pendragon Systems

## 0. Verification status

**Read this first if you are implementing from this document.** Distinguishes
what has been confirmed on the target hardware from what is still assumed.

### Confirmed on target hardware (ublue Kinoite, Ryzen AI Max+ 395)

- Fedora's stock `crun` ships with the krun handler compiled in
  (`+LIBKRUN`), **but `libkrun.so` is not installed by default.** Attempting
  `--annotation run.oci.handler=krun` without it fails with a misleading
  "command that was not found" error that is actually a failed `dlopen`.
  → `crun-krun` (or `libkrun`) must be layered; there is no no-install path.
- `rpm-ostree install crun-krun` is the correct install route on Atomic.
  `--apply-live` works for testing without a reboot.
- Resulting libkrun version is **1.9**, which clears the ≥1.8 floor, so the
  Enter-key bug in coding agents does not apply.
- Rootless `podman run --runtime krun` starts a microVM successfully.
  `/dev/kvm` is accessible to the unprivileged user with no group or udev
  changes; the Fedora 40-era rootless race condition did not reproduce.

The architecture's core assumption — rootless microVM isolation via podman
with no second runtime — is therefore validated on the target machine.

### NOT yet verified — do not assume these work

- **`/workspace` sharing semantics.** Read/write, save latency, and
  particularly whether inotify propagates. Still the highest-risk unknown
  (§4.6). An implementation should not build file-watching-dependent behavior
  on the assumption that it works.
- **Egress filtering.** Where a firewalld policy must attach to actually
  filter guest traffic, given libkrun's networking model (§9). Untested —
  treat the allowlist design as provisional.
- **Runtime scoping in practice.** That `distrobox enter` / `toolbox enter`
  remain unaffected once krun is in the image (§3.1). Expected to hold since
  the runtime is per-container, but unconfirmed on this system.
- **Sizing and latency.** No measurements taken. `.krun_vm.json` values are
  placeholders until measured on a real agent session.

## 1. Goal

Ship a `ujust` recipe so a user runs `claude` (or `pi`, `hermes`) and it
transparently executes inside a microVM — no workflow change visible to the
user, hardware-enforced isolation underneath.

### Non-goals (v1)

- GPU/NPU passthrough. These agents call a remote API; no local inference.
  (Not architecturally closed off — libkrun has a virtio-gpu/Venus path.)
- Multi-user scheduling. Single-user workstation.
- Kubernetes, containerd, or any second container engine.
- Warm-pool VM pre-booting — **not possible under krun**, see §8.

## 2. Threat model

Coding agents execute LLM-generated shell commands and install arbitrary
packages. Assume **the agent may run something malicious or destructive** —
prompt injection, compromised dependency, or plain mistake. The boundary must
survive a kernel-facing exploit attempt, not just a well-behaved-but-buggy
process. That is why this goes to VM isolation rather than stopping at
namespaces + seccomp.

In scope: filesystem access beyond the project dir, network exfiltration to
arbitrary hosts, container/namespace escape, persistence across invocations,
credential theft.

Out of scope: physical access; host kernel 0-days that also break KVM;
supply-chain compromise of podman/crun/libkrun themselves (mitigated by
distro-packaged signed artifacts, not eliminated).

**No root-daemon concession.** This runs rootless — the user needs no
privileged socket access, so there is no root-equivalent group membership to
justify.

## 3. Architecture

```
 host                                       microVM (per invocation)
 ┌────────────────────────────┐             ┌────────────────────────┐
 │ /usr/bin/claude             │             │ libkrun init (root)    │
 │  (wrapper, sole entry pt)   │             │  └─ entrypoint: drop   │
 │        │                    │             │      privs             │
 │        ▼                    │             │      └─ claude-code    │
 │ podman run --runtime krun   │             │                        │
 │        │                    │             │                        │
 │ crun-krun ──> libkrun ──────┼──KVM───────►│ guest (in-process VMM) │
 │                             │             │                        │
 │ agent OCI image ───────────►│─────────────►│ / (rootfs)             │
 │ project dir ───────────────►│──virtio-fs──►│ /workspace             │
 │ cred broker ───────────────►│─────────────►│ token at startup       │
 │ firewalld egress policy ────┼── netavark ─►│ (VM network)           │
 └────────────────────────────┘             └────────────────────────┘
```

No daemon. No second engine. `krun` is an OCI *runtime* — the binary podman
execs to start a container — not an engine. Fedora's stock `crun` already
ships with `+LIBKRUN`; `crun-krun` provides the `krun` binary alongside it.
podman remains the single engine for everything on the image.

### 3.1 CRITICAL: krun must never be the default runtime

**Do not set `runtime = "krun"` in `containers.conf`.** The runtime is
selected per-container at `podman run` time. Setting it globally would apply
microVM isolation to every container on the system, which immediately breaks
`distrobox enter` and `toolbox enter` — both are `podman exec` under the hood,
and **krun does not support `podman exec`** (§8).

Correct model: `--runtime krun` appears *only* in the agent wrapper scripts.
Every other container keeps the default `crun` and behaves exactly as before,
exec included. This is a tempting one-line "simplification" that would break
the rest of the image; call it out in a comment wherever `containers.conf` is
touched.

## 4. Components

### 4.1 Host layer

- **podman** — already present in the ublue base. No change.
- **`crun-krun`** — layered into the AlmanacOS Containerfile. Provides the
  `krun` OCI runtime binary and pulls in `libkrun` as a dependency. **Both are
  required**: stock `crun` has the handler compiled in but not the shared
  library, and the resulting failure message is misleading (§0).
- **libkrun ≥ 1.8** — hard version floor; older versions break the Enter key
  inside coding agents. Current Fedora ships 1.9, so this is satisfied today,
  but assert it at build time anyway so a future rebuild on an older base
  fails loudly rather than shipping a subtly broken agent.
- **Wrapper scripts** (`/usr/bin/claude`, `/usr/bin/pi`, ...) — the single
  owned entry point. Detect `$PWD` and tty-ness, translate expansion flags,
  `exec` into podman so signals and terminal resize pass through.
- **Credential broker** — small host-side service delivering the agent token
  to the guest at startup, so it never lands on a shared filesystem. Transport
  needs settling for krun (§10).
- **Egress allowlist** — firewalld policy scoped to the agent's podman
  network. Default-deny. Raw nftables rules are avoided because ublue ships
  firewalld enabled and it owns its own nft tables.

### 4.2 Kernel prerequisites (stock Fedora/ublue)

- `kvm_amd` — present. User needs rootless access to `/dev/kvm`; verify what
  ublue does by default (`kvm` group membership or udev rule).
- No custom kernel cmdline additions required.
- Nested virt only matters if the agent itself runs VMs — not in v1.

### 4.3 Guest image — built in-repo, not from boxkit

The agent guest image is **a build target in the AlmanacOS repo**, not a
boxkit fork.

Rationale: boxkit is a skeleton for building custom *toolbox/distrobox*
images, and its recommended bases (toolbx community images, ublue toolboxes)
deliberately carry host-integration machinery — sudo, passwd manipulation,
distrobox-init compatibility, a broad package set. For a guest whose entire
purpose is minimal attack surface, inheriting a base designed for maximum host
interop is backwards. The one thing boxkit contributed that this needs —
cosign signing wired into GitHub Actions — already exists in the AlmanacOS
repo with an existing key.

Image contents:

- `FROM fedora-minimal` (or narrower), agent CLI only, no host-integration
  packages.
- Privilege-dropping entrypoint (§4.5).
- `.krun_vm.json` with sizing defaults (§4.4).
- Built and signed by the existing AlmanacOS CI.

Boxkit remains relevant only if AlmanacOS separately wants curated distrobox
images for ordinary dev work — a real thing to want, unrelated to this.

### 4.4 Guest sizing — `.krun_vm.json`

libkrun reads VM settings from OCI annotations or a `.krun_vm.json` at the
root of the container image, annotations taking precedence. Ship defaults in
the image so it carries its own sane sizing:

- `krun.cpus` — defaults to process CPU affinity; set explicitly.
- `krun.ram_mib` — **defaults are too small and will cause OOM kills.** Size
  against a real agent session; a phase-1 measurement, not a guess.

Wrapper flags override per-invocation via `--annotation`.

### 4.5 Guest entrypoint — privilege drop

**The microVM ignores `USER` from the Containerfile and always boots as
root.** The image needs an entrypoint script that explicitly switches to the
unprivileged agent user before exec'ing the agent. Easy to miss, and silently
gives the agent root inside the VM if forgotten — which does not break the VM
boundary, but discards defense-in-depth for free.

### 4.6 Project directory

`$PWD` shared into `/workspace`. Sharing content with processes outside the
krun VM is documented as harder than with a normal container, so **this is the
single highest-risk unknown in the design** — test read/write, save latency,
and inotify behavior early. If inotify doesn't propagate, agents with
file-watching features will misbehave confusingly.

## 5. First-run authentication

The broker assumes a token already exists on the host, but initial login is
typically a browser OAuth flow that cannot complete inside a headless guest
behind a default-deny allowlist.

1. `ujust agent-login` runs the OAuth flow **on the host**, where a browser
   exists, and stores the token for the broker.
2. The broker serves it to guests at startup.
3. Prefer a device-code flow where the agent supports one — needed anyway for
   the eventual headless/miniPC variant.

**Prerequisite for the allowlist:** enumerate every host the agent actually
contacts — API endpoint, telemetry, update checks, package registries. A list
allowing only the API endpoint produces confusing partial failures instead of
clean errors.

## 6. Wrapper script (skeleton)

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$PWD"
INVOCATION_ID="$(uuidgen)"
IMAGE="localhost/agent-sandbox:latest"

TTY_FLAGS=()
[ -t 0 ] && [ -t 1 ] && TTY_FLAGS=(-it)

almanac-cred-broker register "$INVOCATION_ID"

exec podman run --rm "${TTY_FLAGS[@]}" \
  --runtime krun \
  --network agent-restricted \
  --volume "$PROJECT_DIR:/workspace" \
  --workdir /workspace \
  --env "ALMANAC_INVOCATION_ID=$INVOCATION_ID" \
  --env "TERM=${TERM:-xterm-256color}" \
  "$IMAGE" \
  claude-code-real "$@"
```

`--runtime krun` is scoped to this invocation only (§3.1). CPU/RAM come from
the image's `.krun_vm.json`; expansion flags (`--cpus`, `--ram`, `--net=`,
`--extra-mount=`) map to `--annotation` and firewalld policy updates.

## 7. Build pipeline

1. **AlmanacOS repo, agent image target** — minimal Containerfile, agent CLI,
   privilege-dropping entrypoint, `.krun_vm.json`. Signed with the existing
   cosign key by existing CI.
2. **AlmanacOS Containerfile** — layer `crun-krun`, assert the libkrun version
   floor, install wrapper scripts to `/usr/bin`.
3. `ujust update-agent-sandbox` pulls the latest signed agent image.
   `crun-krun` updates with the OS image.

## 8. Known limitation: no `podman exec`

krun does not support `podman exec` — there is no mechanism to launch a new
process into a running microVM. Consequences:

- The per-invocation `podman run --rm` design is unaffected.
- **Warm-pool latency optimization is permanently off the table** under krun.
  If cold-boot latency is intolerable after phase 1, the answer is not
  "pre-boot and exec into it" — it's revisiting the isolation tier for that
  use case.
- **distrobox/toolbox can never be the UX for a krun-isolated environment**,
  since both are `podman exec`. This costs nothing here (they were ruled out
  for the agent case on other grounds), but it does mean the two approaches
  can't be merged later.
- Debugging is via logs and fresh invocations, not shelling into a live VM.

## 9. Open questions

- **Credential broker transport under krun.** Whether libkrun exposes a
  host-side control channel comparable to Kata's vsock, or whether this becomes
  a loopback/TSI-based service on the guest network, or an injected value at
  create time. The requirement stands regardless: the token must not sit on a
  shared filesystem.
- **Networking model.** libkrun uses passt/pasta-style user-mode networking in
  some configurations; confirm how it composes with podman's netavark network
  and where the firewalld policy must attach to actually filter guest egress.
- ~~**Rootless stability.**~~ Resolved — rootless krun starts reliably on the
  target hardware with current Fedora (§0). The Fedora 40-era race did not
  reproduce.
- **Per-agent images vs. one shared image.** Shared is simpler to build and
  sign; per-agent is a smaller attack surface each. Leaning shared for v1.
- **Does a bwrap tier still have a role?** With the two-runtime objection gone,
  krun may simply be the default everywhere including the headless variant.
  Keep a bwrap fallback only if phase-1 measurements show microVM overhead is
  unacceptable on constrained hardware.

## 10. Phased implementation

Testing happens on the deployed Almanac image rather than via a separate
manual PoC stage. This is viable because `.krun_vm.json` defaults are
overridden by `--annotation` at runtime — sizing and `/workspace` behavior can
be tuned on a running system without rebuilding. Only `crun-krun` presence and
the wrapper scripts require a new image build.

**Phase 0 — pre-build smoke test. ✅ DONE.** Rootless krun confirmed working
on the target machine, libkrun 1.9, `/dev/kvm` accessible without group
changes. See §0. The architecture is validated; remaining work is packaging
and the unverified items listed there.

1. **Build it in**: `crun-krun` layered in the AlmanacOS Containerfile with the
   libkrun version floor asserted; minimal agent guest image as a repo build
   target with privilege-dropping entrypoint and starting `.krun_vm.json`;
   wrapper scripts to `/usr/bin`. Deploy.
2. **On-device validation**: full agent session end-to-end. Confirm Enter works
   in the agent, `/workspace` read/write and inotify behave, and
   `distrobox enter` still works normally (i.e. krun stayed scoped, §3.1).
   Measure boot latency and real RAM use with `--annotation` overrides, then
   fold the resulting numbers back into `.krun_vm.json` on the next build.
3. **Wrapper v1**: `$PWD` mount, token via env var (not the target state, but
   unblocks testing).
4. **Credential broker**: resolve transport, drop env-var passing, add
   `ujust agent-login`.
5. **Egress allowlist**: firewalld policy after enumerating the agent's real
   endpoint list. Test a full session.
6. **Update durability**: verify the whole thing survives an image update —
   wrappers, `crun-krun`, and `ujust` recipes all still present and working on
   a second deployment.

## 11. Risks

- **`/workspace` sharing semantics** are the top technical unknown (§4.6).
  Everything else is packaging; this one could force a design change — and
  because validation now happens post-deploy, discovering it costs an image
  rebuild rather than a config change. Accepted trade for a simpler workflow.
- **Boot latency per invocation** with no warm-pool escape hatch (§8). Measure
  on-device, don't assume.
- **Global-runtime footgun** (§3.1). Setting krun as the default in
  `containers.conf` breaks distrobox/toolbox across the whole image. Guard with
  a comment and, ideally, a CI check on the shipped `containers.conf`.
- **krun is a smaller-community path than plain crun.** Real production users
  exist (Red Hat's RamaLama uses this exact mechanism for microVM-isolated AI
  workloads), and Fedora Magazine published a June 2026 walkthrough of
  sandboxing AI coding agents this way — but expect occasional rough edges.
- **Silent misconfiguration modes**: undersized RAM (OOM kills), forgotten
  privilege drop (agent runs as root in-guest), stale libkrun (Enter key
  broken). All three are cheap build-time assertions; do that rather than
  documenting them.
