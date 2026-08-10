# Agent Sandbox — Implementation Plan

Companion to `SPEC.md` (draft rev 5). The spec says *what* and *why*; this says
*what to change, in what order, and how to know it worked.*

## Context

AlmanacOS ships `lemonade` for local inference and `amf` for airgapped model
import. It does not yet have a story for the other kind of AI workload on the
machine: coding agents that execute LLM-generated shell commands against a real
project directory. `SPEC.md` argues that boundary needs to be a VM, not a
namespace, and that `podman --runtime krun` gets there with no second container
engine and no root daemon. Phase 0 confirmed rootless krun boots on the target
hardware.

What is missing is everything downstream of that: the runtime isn't in the
image, there is no guest image, there is no entry point, and there is no
credential or egress story. This plan covers all six phases of §10.

## Decisions locked in

| Question | Decision |
|---|---|
| Scope | All six phases of §10 |
| Agents | `claude`, `opencode`, `pi`, `hermes` — all installed via npm |
| Entry point | Single `/usr/bin/agentbox` dispatcher, opt-in. **Does not shadow host `claude`.** |
| Guest image | One shared image, per-agent installs kept in separate build stages so a split is a build-arg change |
| Distribution | GHCR via the existing workflow, cosign-signed with the existing `SIGNING_SECRET` key |
| libkrun version floor | Dropped (see below) |

## Corrections to the spec

Research turned up four things that change the design. These should be folded
back into `SPEC.md` when the work lands.

**1. §0 misstates the libkrun version.** Fedora 43 ships **libkrun 1.19.0**, not
1.9. The ≥1.8 floor is satisfied by a wide margin, so per your call the assert
is dropped — but note that `1.19.0` vs `1.8` compares correctly only under
rpmvercmp semantics; any future check must not use lexical `sort`. Also worth
knowing: `libkrun` pulls in `libkrunfw` (a bundled guest kernel), `pipewire`,
and `virglrenderer`. That is real image weight for a feature with no GPU
passthrough in v1.

**2. `crun-krun` is a symlink package.** It contains exactly `/usr/bin/krun`
(a symlink to `crun`) plus a man page — 17 KB. The krun handler is compiled into
the stock `/usr/bin/crun`. Its `Requires: libkrun` is **unversioned**.

**3. §4.1's egress design is not implementable as written.** libkrun defaults to
TSI, not virtio-net: *"TSI for AF_INET and AF_INET6 is automatically enabled when
no network interface is added to the VM."* Under TSI **there is no guest IP and
no guest interface** — the VMM proxies guest sockets as host sockets. libkrun's
own README: *"the VMM and the guest should be considered to be running in the
network context. As such, you should apply on the VMM whatever restrictions you
want to apply on the guest."* A firewalld policy object scoped to a podman
network has no guest source address to match on, and firewalld runs as root in
the host netns where rootless pasta traffic does not appear as a distinguishable
flow. §9's open question resolves to: **the firewalld approach does not work.**
See "Phase 5" for what replaces it.

**4. §4.5's privilege drop may conflict with §4.6's writable `/workspace`.**
podman#28316 — *"Libkrun: bind mounted volumes are always read-only for
container users other than root"* — is open and unassigned. If it reproduces on
Linux, dropping to an unprivileged guest user makes the project directory
read-only, which breaks every agent. This is a hard fork in the road and Phase 2
must resolve it before Phase 3 is worth writing.

Additionally, **podman#28067** (open since 2026-02-11) reports that under
`run.oci.handler=krun`, TUI applications — `htop`, `nvim`, and `claude`
specifically — cannot process the Enter key. Per your call the plan assumes this
works, but it is listed first in the Phase 2 checklist because it invalidates
the entire interactive-wrapper UX if it reproduces.

---

## Phase 1 — Get it into the image

**Status: implemented.** Every subsection below is landed except where it says
otherwise. What is *not* verified is anything requiring the image to be built
and booted — that is Phase 2, and it is where the two open podman bugs get
answered.

### 1a. Host runtime — `build_files/build.sh`  ✅

Add to the Fedora-repo install section (`crun-krun` and `libkrun` are both in
`updates`, so no COPR sandwich is needed):

```bash
# Agent sandbox: krun OCI runtime for microVM-isolated coding agents.
# crun-krun is just a /usr/bin/krun symlink to crun; libkrun is the shared
# library crun dlopen()s. Stock crun has the handler compiled in but not the
# library, and the failure without it is a misleading "command not found".
dnf5 install -y crun-krun libkrun
```

`jq` goes in the same line — it is what `almanac-agentbox` reads the agent
registry with.

`build.sh` also now:

- installs `agent_image/agents.json` to `/usr/share/almanac/agents.json`, so the
  host registry and the guest registry are the same file rather than two files
  that agree today. This needed one line in the root `Containerfile` to put
  `agent_image/` into the build context stage.
- merges the signature policy fragment (1f) into the base image's
  `policy.json`.
- `chmod +x /usr/libexec/almanac-agentbox` and symlinks it to
  `/usr/bin/agentbox`.

**Do not** create `/etc/containers/containers.conf`, and do not set
`runtime = "krun"` anywhere. §3.1 is load-bearing: a global default would break
`distrobox enter` and `toolbox enter` across the whole image, because both are
`podman exec` and krun does not implement exec (crun#2090). Guard it with a CI
check — see 1d.

### 1b. Guest image — new `agent_image/` directory  ✅

```
agent_image/
├── Containerfile          # multi-stage, one stage per agent
├── krun_vm.json           # installed to /.krun_vm.json
├── entrypoint             # privilege drop, then exec the agent
└── agents.json            # registry: name → guest command + description
```

`Containerfile` — `FROM registry.fedoraproject.org/fedora-minimal:43`,
`microdnf install nodejs npm git ca-certificates util-linux-core`, then one
`RUN npm install -g` layer **per agent**, each guarded by an `ARG
WITH_<AGENT>` *and* an `ARG <AGENT>_PACKAGE`. That is what "shared now,
structured to split later" buys: a claude-only image is
`--build-arg WITH_OPENCODE=0`, and pinning a version is
`--build-arg CLAUDE_PACKAGE=@anthropic-ai/claude-code@1.2.3`. Neither is a
rewrite.

No sudo, no distrobox-init, and no shadow-utils — §4.3's whole point. The
`agent` user is created by appending to `/etc/passwd` and `/etc/group`
directly, because an image that carries `useradd` hands a compromised agent a
way to make itself a second account.

**`pi` and `hermes` are `WITH_*=0` by default.** Their npm package names are
recorded nowhere in this repo and I will not guess one — a wrong guess ships an
image whose `pi` is somebody else's package. Set `PI_PACKAGE` / `HERMES_PACKAGE`
and flip the toggle, in the same commit that flips `"built": true` in
`agents.json`. The build fails loudly if a toggle is on with an empty package
rather than producing an image that is quietly missing an agent.

`krun_vm.json` → **`/.krun_vm.json` at the rootfs root** (crun's
`KRUN_VM_FILE` constant; opened `O_NOFOLLOW`, so it must be a real file, not a
symlink):

```json
{
  "cpus": 4,
  "ram_mib": 8192
}
```

Note the asymmetry, which is easy to get wrong: the **JSON keys are bare**
(`cpus`, `ram_mib`) while the **annotations are prefixed** (`krun.cpus`,
`krun.ram_mib`). Annotations win over the file. libkrun's own defaults are
1024 MiB RAM and CPU-affinity-derived cpus — 1 GiB will OOM-kill a coding agent,
which is §11's "undersized RAM" risk. 8192 is a placeholder to be replaced with
Phase 2 measurements.

`entrypoint` — §4.5. Assume the OCI `USER` is ignored and the VM boots as root;
this is consistent with crun's handler source (it never reads
`def->process->user` and never calls `krun_setuid`/`krun_setgid`), though no
maintainer statement confirms it. The entrypoint `exec setpriv --reuid=agent
--regid=agent --init-groups -- "$@"`. **Phase 2 decides whether this survives
the read-only-volume bug**; write it so the drop can be disabled by an env var
while that is being tested.

### 1c. Host entry point  ✅

Following the repo's existing split — logic in `libexec`, thin name in `bin`:

- `system_files/usr/libexec/almanac-agentbox` — the real script
- `system_files/usr/bin/agentbox` — symlink to it
- `system_files/usr/share/almanac/agents.json` — the agent registry, same file
  shipped into the guest image, so host and guest cannot disagree about what
  exists

Match the house style already set by `almanac-memory` and `almanac-models`:
`#!/usr/bin/bash`, `set -euo pipefail`, a purpose comment block at the top,
`die()`/`warn()` using `printf` to stderr prefixed with the script name,
`usage()` as a heredoc with an `Environment:` section, `main()` dispatching on
`$1` at the bottom. Env knobs get the `ALMANAC_` prefix.

Core of it, expanding §6's skeleton:

```bash
exec podman run --rm "${TTY_FLAGS[@]}" \
  --runtime krun \
  --annotation krun.cpus="$CPUS" \
  --annotation krun.ram_mib="$RAM_MIB" \
  --volume "$PROJECT_DIR:/workspace:Z" \
  --workdir /workspace \
  --env "TERM=${TERM:-xterm-256color}" \
  --env "$TOKEN_VAR" \
  "$IMAGE" "$GUEST_CMD" "$@"
```

Three details that matter:

- `--runtime krun` appears **only here** (§3.1).
- `--env "$TOKEN_VAR"` — the *name only*, no `=value`. Podman inherits the value
  from the wrapper's environment, so the token never appears in the wrapper's
  argv and therefore never in `ps`.
- No `--device /dev/kvm`. crun's krun handler creates the device inside the
  container itself.

CLI surface: `agentbox <agent> [args...]`, `agentbox --list`, and the expansion
flags from §6 (`--cpus`, `--ram`, `--net`, `--extra-mount`) translated to
annotations and mounts.

### 1d. Build pipeline

**Done** — landed ahead of the rest of Phase 1, since nothing else in `agent_image/`
can be built until this exists. What shipped:

- **`Justfile`** — `build` took two new trailing parameters, `$containerfile`
  (default `Containerfile`) and `$description` (default `$image_desc`), and the
  `org.opencontainers.image.title` label now reads `${target_image}` instead of
  `{{ image_name }}` so the two images do not both claim to be AlmanacOS. Both
  are no-ops for the existing OS build. New variables `agent_image_name`
  (`lowercase(IMAGE_NAME) + "-agent"` → `almanacos-agent`; OCI repository names
  must be lowercase and `IMAGE_NAME` is not) and `agent_image_desc`, a private
  `agent_image_name` recipe mirroring `image_name` for CI to call, and
  `build-agent-image` as a thin dependency on `build`.
- **`.github/workflows/build-agent.yml`** — a **separate workflow**, not a second
  job inside `build.yml`. This revises the earlier draft of this section. Four
  reasons the split is better than a sibling job:
  - The two images have unrelated lifecycles. The OS image rebuilds on base
    image updates; the guest image should rebuild when the agents' npm packages
    release. They want different `schedule:` cadences, and a job cannot carry
    its own trigger.
  - `build.yml`'s `concurrency` group has `cancel-in-progress: true`. Sharing it
    means a guest image push cancels an in-flight OS build, and vice versa.
  - `paths:` filters are per-workflow. Split, a change under `agent_image/`
    builds only the guest image (`build.yml` now `paths-ignore`s it), and a
    change under `system_files/` builds only the OS image.
  - No shared `/tmp/digestfile`, by construction rather than by care.

  It reuses `generate-build-tags`/`tag-images` unchanged and the same
  `SIGNING_SECRET`, and pushes to `ghcr.io/clemperorpenguin/almanacos-agent`.
  No rechunk and no `bootc container lint` — both are bootc concerns and this is
  a plain OCI rootfs.
- **Digest guard** — the push loop in *both* workflows now asserts that every
  tag push reports the same digest and fails if not, instead of taking whatever
  the last iteration happened to leave in `/tmp/digestfile`. Today all tags
  resolve to one image ID (`tag-images` untags and re-tags a single ID), so this
  never fires; it exists so that stops being an unchecked assumption.
- **Not yet wired**: `build-agent.yml` has no `schedule:` trigger. `schedule`
  ignores `paths:` filters, so it would fail nightly until
  `agent_image/Containerfile` exists. Add it in the commit that adds 1b — there
  is a `TODO` at the trigger block.
- **CI guard for §3.1** — a step (or a `just` recipe called from `just check`)
  that greps `system_files/` for `runtime\s*=\s*"?krun` and fails. This is the
  "tempting one-line simplification" the spec asks to be defended against, and
  §11 explicitly asks for it.
- `just check` runs `just --unstable --fmt --check` over every `*.just` in the
  tree, so the new recipes must be fmt-clean or CI fails at the first step.

### 1e. ujust recipes — `system_files/usr/share/ublue-os/just/60-almanac.just`  ✅

Append, matching the existing `[group('Almanac')]` / quoted-`{{ }}` style:

Three recipes landed — `almanac-list-agents`, `almanac-agent-status`, and
`almanac-update-agent-sandbox`. The `almanac-agent-login` and
`almanac-agent-egress` recipes sketched in earlier drafts are **deliberately
held back** to Phases 4 and 5: a `ujust` entry that prints "not implemented yet"
is worse than no entry, because it advertises a control the sandbox does not
actually have.

Running an agent is not a `ujust` recipe. `ujust` cannot forward arbitrary
trailing arguments cleanly, and agents take a lot of them. `agentbox <agent>
[args...]` on `PATH` is the interface.

### 1f. Image signature verification  ✅

The repo signs images but shipped no verification policy. Rather than requiring
the `cosign` binary at runtime — it is not in the base image — verification
happens at pull time via three pieces:

- `system_files/etc/pki/containers/almanacos.pub` — a copy of the repo's
  `cosign.pub`.
- `system_files/etc/containers/registries.d/ghcr.io.yaml` — sets
  `use-sigstore-attachments: true` for `ghcr.io/clemperorpenguin`. Without this
  the stack never looks for the `sha256-<digest>.sig` artifact cosign pushes,
  and every pull fails with "missing signature" while the signature sits in the
  registry untouched.
- `system_files/usr/share/almanac/agent-policy.json` — a **fragment**, merged
  into the base image's `/etc/containers/policy.json` by `build.sh` rather than
  replacing it. This is the one departure from the earlier draft: shipping a
  `policy.json` in `system_files/` would clobber whatever ublue and Fedora put
  there, silently changing how every unrelated pull on the system is verified.
  The merge preserves existing transports and adds one scope.

Scope is a single repository. A `default: reject` policy, or a broader scope,
would break Flatpak runtimes, toolbox images, and bootc's own pull of the OS
image, none of which are signed with this key.

`podman pull` then enforces the signature itself, so
`almanac-update-agent-sandbox` needs no verification logic of its own: a pull
that succeeds is a pull that was signed.

---

## Phase 2 — On-device validation

Run on the deployed image, in this order. Items 1 and 2 are gates: if either
fails, stop and revisit the design rather than continuing to Phase 3.

1. **Enter key in a TUI.** `agentbox claude`, type a prompt, press Enter.
   Also `htop` and `nvim` inside the guest. This is podman#28067; if it
   reproduces, the transparent-wrapper UX is dead and the alternative is a
   non-interactive/headless invocation mode.
2. **`/workspace` writability with the privilege drop active.** Create, modify,
   and delete a file as the unprivileged guest user. This is podman#28316. If it
   fails, the choice is between the privilege drop and a writable project dir —
   take the writable project dir, since the VM boundary is what the threat model
   actually rests on, and record the loss.
3. **inotify.** Touch a file on the host, watch for the event in the guest
   (`inotifywait -m /workspace`). Expect this to **fail** — virtiofs has no
   fsnotify propagation upstream (LWN 874000; the RFC series never merged).
   Confirm and document, then verify each agent degrades tolerably rather than
   hanging.
4. **Runtime scoping.** `distrobox enter` and `toolbox enter` still work
   normally, and `podman run` without `--runtime` still uses crun (§3.1).
5. **Sizing.** Run a real agent session with
   `--annotation krun.ram_mib=<n>` sweeps; record peak RSS and cold-boot
   latency. Fold the numbers into `krun_vm.json` on the next build.

---

## Phase 3 — Wrapper v1  ✅

Phase 1 shipped the skeleton; this closes what Phase 2 exposed. Token passing is
`--env` by name, which per Phase 4 is already the target state rather than a
stopgap, so it did not change.

**Sizing is now three-tiered** — `--cpus`/`--ram` or the env vars, then per-agent
`cpus`/`ram_mib` in `agents.json`, then `DEFAULT_CPUS`/`DEFAULT_RAM_MIB`. The
per-agent tier exists because the VM commits its memory up front, so a single
figure across four agents is either wasteful for the small ones or fatal for the
large ones. **The committed per-agent values are the defaults carried forward,
not measurements.** Phase 2 item 5 produces real numbers; they go in
`agents.json` and nowhere else.

**inotify is dead over virtiofs, so watchers poll.** This was the expected Phase
2 result and it is the one that would otherwise bite silently: node's watchers
do not error when inotify never fires, they just never fire, so the agent simply
never notices a host-side edit. The guest image now sets
`CHOKIDAR_USEPOLLING=1`, `CHOKIDAR_INTERVAL=1000` and `WATCHPACK_POLLING=true`.
Baked into the image rather than the wrapper because it is a property of the
filesystem the guest runs on, not of any particular invocation, and overridable
per-run with `--env CHOKIDAR_USEPOLLING=0` on a tree too large to poll.

**Git identity is forwarded.** The guest has git but no gitconfig, and the
host's is deliberately not mounted — it carries credential helpers, signing
keys, and `insteadOf` rules, which is precisely the ambient authority the
sandbox exists to withhold. But an agent asked to commit then hits "Please tell
me who you are", and agents respond to that by inventing an identity. Only
`user.name` and `user.email` cross, as `GIT_AUTHOR_*`/`GIT_COMMITTER_*` — two
values already public in every commit the user has pushed.

**Terminal and locale cross too**: `COLORTERM`, `LANG`, `LC_ALL`, `LC_CTYPE`,
`TZ`, `NO_COLOR`, `FORCE_COLOR`, forwarded by name where set. A TUI in a VM with
no locale renders box-drawing characters as mojibake, and without `TZ` every
timestamp the agent prints is UTC with nothing saying so.

**`agentbox ps`**, plus `--name` and `almanac.*` labels on every VM. There is no
`agentbox exec` and never will be (crun#2090), so identifying a sandbox and
stopping it is the entire management story; being unable to list them made that
zero.

**First run pulls instead of failing.** `ensure_image` offers the pull when
interactive and dies with the `ujust` instruction when not. Safe to offer
because the signature policy gates the pull — there is no path here that fetches
something unverified in order to be helpful.

One implementation note worth keeping, because it is a trap the whole script's
by-name convention walks into: `setup_git_identity` sets a global array rather
than printing flags like its neighbours. The `export` has to happen in the
wrapper's own shell for podman to inherit it, and a function whose output is
captured by `< <( )` runs in a subshell whose environment is discarded — so
printing `--env GIT_AUTHOR_NAME` from a subshell that also exported it yields a
flag naming a variable podman cannot see.

### Verified how

By dry run with stubbed `podman` and `jq`, on the assembled argv: sizing
precedence, per-agent fallback, credential forwarding, unknown/unbuilt agent
refusal, `$HOME` refusal, and passthrough of trailing agent arguments. The
security property that matters — the token appearing as `--env ANTHROPIC_API_KEY`
and the value appearing nowhere in argv — is checked directly.

Still unverified, and only Phase 2 hardware can settle it: whether the polling
interval is tolerable on a large repository, and whether the per-agent sizing
defaults are anywhere near right.

---

## Phase 4 — Credentials  ✅

**The broker is dropped.** §5/§9 wanted one so the token "never lands on a
shared filesystem", and an env var passed by name satisfies that exactly: the
value lives in the wrapper's memory and the guest's memory, never on the
virtiofs share, never in the image, never in argv. A vsock service would add a
protocol and an attack surface to deliver the same secret to the same untrusted
party.

And no transport mitigates the actual threat. The guest needs the token to
function, so a compromised agent has it by construction whatever channel
delivered it. What reduces exposure is the credential's *shape* — short-lived,
narrowly scoped, revocable — which is where this phase's effort went.

### What the store is actually for

Not defence against the agent. The problem it solves is narrower and real: the
agents' interactive logins want a browser, the sandbox has neither a browser nor
a persistent home, and so every session would start unauthenticated. The obvious
fix — bind-mounting `~/.claude` or `~/.local/share/opencode` into the guest —
hands the agent the entire credential store including whatever else is in it.

So: log in once on the host, keep the token in a store of our own, and hand
exactly one token to exactly one agent at run time. The store never crosses the
boundary.

### Shape

- `agentbox login <agent>` reads the token with `read -rs`, so it is never
  echoed, never in scrollback, never in shell history, and never in argv.
- Stored at `${XDG_STATE_HOME:-~/.local/state}/almanac/agent-creds/<agent>.json`,
  file `0600`, directory `0700`, written under `umask 077`. Under `$HOME`, so it
  survives `bootc upgrade` for free — and deliberately not under `/var`, which
  `bootc container lint` polices.
- `agents.json` grew a `credential` record: `env` (the variable the token is
  presented as), `obtain` (a command that *prints* a token, or `null`), `note`.
- Where `obtain` exists, `login` offers to run it in a **throwaway sandbox with
  no project mounted** and `/workspace` on tmpfs. That matters because the agent
  need not be installed on the host at all — the whole point is that it is not.
  A device-code flow prints a URL, the operator opens it in the host browser.
- For claude that is `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN`, a
  headless token that can be revoked without touching the account key. Preferring
  it over `ANTHROPIC_API_KEY` *is* the credential-shape argument in practice.
- opencode's `auth login` writes a credential file rather than printing a token,
  and that file would have to be mounted into the guest to be useful — which is
  the thing being avoided. So `obtain` is `null` and the operator pastes a
  provider API key, which every provider opencode supports accepts by
  environment variable.

### Resolution order, and one guard

A variable already set in the caller's shell wins; the store is the fallback.
Loading the store on top would duplicate the `--env` flag and silently override
what the operator typed.

`--mount` refuses any source at or under the credential directory. Mounting a
parent directory by accident is easy, and it would undo the whole arrangement in
one flag.

`logout` says plainly that it does not revoke anything. If the reason someone is
running it is a leak, the upstream revocation is the step that matters and this
was not it.

### Verified how

Driven through a pty with stubbed `podman`/`jq`: `login` stores `0600` in a
`0700` directory; a run with a stored credential passes `--env
CLAUDE_CODE_OAUTH_TOKEN` and **the token value appears nowhere in the assembled
argv**; a shell-set variable produces exactly one flag rather than two;
`--mount` of the store is refused; `status` reports credential state per agent
without printing any; `logout` removes the file. `login` correctly refuses to
run without a tty.

---

## Phase 5 — Egress  ✅ (layer 1) / ⚠️ (layer 2)

The spec's firewalld design does not work, for the reason in correction 3: under
TSI the guest has no IP and no interface, so a policy scoped to a podman network
has nothing to match on. What replaced it splits policy from enforcement,
because they need different mechanisms — and the honest result is that only one
of the two is finished.

### Layer 1 — policy: `almanac-agent-proxy`  ✅

A filtering CONNECT proxy, stdlib Python, run as a **user** systemd service. It
reads the hostname from `CONNECT host:port`, checks an allowlist, and splices or
refuses. Hostname granularity is not a nicety: every endpoint these agents use
sits behind a CDN with rotating addresses, so an IP allowlist is wrong within
the week. The `CONNECT` line is the last place the hostname is legible before
TLS starts.

No TLS interception, so no CA generation and nothing injected into the guest's
trust store. Only ports 80 and 443, so an allowlisted hostname does not double
as permission to reach every service on that host. The allowlist reloads on
mtime change, so `egress allow` takes effect without a restart.

`agentbox egress show | allow | deny | log | test | probe`, plus
`ujust almanac-agent-egress`. The system list is at
`/usr/share/almanac/agent-egress.conf` and is replaced on image update; user
additions go to `~/.config/almanac/agent-egress.conf` and are never overwritten.

**The shipped list is a starting point, not an enumeration.** §5 asks for every
host each agent contacts; what is committed is what the agents are documented or
observed to use — npm, GitHub's four hosts, the Anthropic endpoints, models.dev,
OpenAI, OpenRouter. A missing entry does not fail cleanly, it hangs, which is
why `egress log` exists and is pointed at from the failure message.

### Layer 2 — enforcement: `--net`  ⚠️

Three modes, and the split between them is the whole point:

| mode | what it does | enforced? |
|---|---|---|
| `open` (default) | no restriction | — |
| `filtered` | guest pointed at the proxy via `HTTPS_PROXY` | **no** |
| `none` | `--network none`; the VMM's namespace has no route | **yes** |

`filtered` is advisory. An agent that ignores `HTTPS_PROXY` and opens a socket
is unaffected by anything in layer 1. It buys a log of what the agent reaches
and a stop on accidental traffic — worth having, not worth trusting.

`filtered` is deliberately **not** the default. Defaulting to it would describe
the sandbox as network-restricted when it is not, and a boundary people believe
in but which does not hold is worse than an absent one.

`none` is genuinely enforcing, because under TSI the guest's sockets *are* the
VMM's sockets and the VMM is in a namespace with nothing but loopback. It is
also the only mode that costs the agent its network entirely.

### The gap, and why it ships as a probe

The design that would give both — default-deny *and* usable egress — is
`--network none` plus the proxy reachable over a **bind-mounted AF_UNIX socket**,
since TSI proxies AF_UNIX as well as AF_INET. That would be a real boundary with
exactly one deliberate hole.

It is unverified. It depends on whether libkrun carries a bind-mounted socket
into the guest, and on whether the agents' HTTP clients accept a unix-socket
proxy. Shipping it as the default would mean shipping an untested security
boundary, which is the one thing worse than shipping none.

So it ships as `agentbox egress probe`: it starts a proxy on a unix socket,
boots a sandbox with `--network none`, and reports whether the socket was
reachable. **Run it on hardware.** If it passes, strict mode is achievable here
and this section should be rewritten; if it fails, `--net none` stays the only
enforcing option and that is worth writing down too. The proxy already listens
on `--unix-socket` in anticipation.

Also unresolved and only answerable on-device: whether `host.containers.internal`
resolves from inside the guest under the rootless network backend in use. That
is how `filtered` addresses the proxy, and `ALMANAC_AGENT_PROXY_HOST` overrides
it when it does not.

### Verified how

The proxy is the one component in this whole design that runs fully on a
development machine, so it is properly tested rather than dry-run: 13 checks,
all passing. Allowlist matching including case-insensitivity, trailing dots,
wildcards, and two confusion attacks — `api.anthropic.com.evil.com` and
`notapi.anthropic.com` both correctly refused, and `*.npmjs.org` correctly does
*not* grant the bare apex. Protocol behaviour: 403 for unlisted host, 403 for a
non-web port, 501 for non-CONNECT, 400 for a malformed target. End to end
against the live network: a real TLS session to `api.anthropic.com` through the
tunnel, a 403 for a denied host, and a live allowlist reload taking effect
without a restart.

Wrapper side, dry-run: `--net none` emits `--network none`, `--net open` emits
nothing, an unknown mode is refused, and `egress allow`/`deny`/`show` round-trip
— including removing the only entry, which exposed a `set -e` bug where `grep
-v` exits 1 after filtering out every line and killed the command before it
reported success.

---

## Phase 6 — Update durability

After a second `bootc upgrade`: `agentbox` present and executable, `krun` still
installed, ujust recipes still listed, the agent image still pulls and verifies,
credentials in `~/.local/state` survived, and `distrobox enter` still works.
`bootc container lint` runs at the end of every build and will flag anything
unusual added to the image root — including, notably, content under `/var`,
which is why nothing in this design stores state there.

---

## Verification

Per-phase checks are inline above. End to end, on the deployed image:

```bash
ujust almanac-agent-status          # krun present, /dev/kvm ok, image + signature
ujust almanac-update-agent-sandbox  # signature-verified pull
ujust almanac-agent-login claude
cd ~/some-project && agentbox claude
```

Then, from inside a session: write a file in `/workspace` and confirm it appears
on the host; try to read `~/.ssh` and confirm it is not there; try to curl a
host outside the allowlist and confirm it fails.

Pre-merge, on the build side: `just check` (just fmt + the new krun-default
guard), `just build` and `just build-agent-image` locally, and confirm the new
CI job pushes and signs to `ghcr.io/clemperorpenguin/almanacos-agent`.

## Known-unresolved

- podman#28067 (Enter key in TUIs under krun) — assumed working per your call,
  tested first in Phase 2.
- podman#28316 (bind mounts read-only for non-root guest users) — forces a
  choice between §4.5 and §4.6 if it reproduces.
- inotify over virtiofs — expected broken; affects agents with file watchers.
- Whether TSI carries a bind-mounted AF_UNIX socket, which decides the Phase 5
  enforcement mechanism.
- `docs/` is currently untracked (`?? docs/`). Both `SPEC.md` and this file
  should be committed with the first phase.
