# Offline model import — design

Why `almanac-models` is shaped the way it is. For how to use it, see
[OPERATING.md](OPERATING.md).

## 1. The problem

An AlmanacOS machine is sometimes expected to run with no network. Models still
have to get onto it, and they arrive the only way anything arrives at an
airgapped machine: someone carries them in on a drive.

That makes the drive the attack surface. Everything on it was written somewhere
else, by something the importing machine cannot observe, and it arrives with no
live channel to check it against — no keyserver, no CRL, no upstream API, and
not necessarily a correct clock. Whatever assurance the import has must come
from bytes already on the machine before the drive was plugged in.

## 2. What is checked, and what each check proves

`amf` performs five checks. `almanac-models` invokes them; it does not implement
any of them. Strongest last:

1. **Every model file hashes to what the manifest says.** Detects corruption and
   a flipped byte.
2. **The manifest's own digest matches the file list.** Detects an edited
   manifest.
3. **Every evidence file hashes to what the manifest says.** Detects evidence
   swapped for a different repo's.
4. **The git chain is re-derived offline** — commit → trees → LFS pointers →
   the SHA-256 the model was checked against. Detects a manifest whose hashes
   were never what upstream published.
5. **The fetcher's minisign signature over the manifest.** Detects a bundle
   nobody you trust produced.

Checks 1–4 establish that a bundle is *internally consistent*. So does a
well-made forgery: an attacker who writes the manifest, the evidence and the
model together satisfies all four trivially. Only check 5 is anchored outside
the drive, in a key that was carried here separately.

**So import gates on 5 and nothing else.** Without a readable
`/etc/almanac/amf.pub` it refuses, and `ALMANAC_ALLOW_UNSIGNED=1` is the only way
past — deliberately an environment variable rather than a flag, deliberately
noisy, and it prints what it is giving up before it proceeds.

`verify` does *not* gate. It is a diagnostic: running it keyless is useful, so it
runs and warns precisely about what it could not check, instead of refusing and
teaching people to skip it.

The upstream commit-signing key (`--upstream-key`) is never picked up
automatically even when present. Passing it fails every bundle from a host that
does not sign its commits at all — ModelScope's normal state, not a fault — and
a check that fires on a normal condition is a check people learn to ignore.

## 3. Verify the copy, not the original

Bundles are copied into a staging directory and verified *there*, rather than
verified on the drive and copied afterwards.

The ordering costs nothing: one full read of the drive either way. What it buys
is that the bytes that were checked are the bytes that get installed. Verifying
in place and then copying leaves a window — the drive is removable, mounted, and
possibly writable by something else — between the check and the thing the check
was supposed to authorise.

A bundle that fails is deleted from staging. It never appears in the directory
Lemonade scans, not even briefly.

## 4. Promotion is a rename

The staging area sits at `$(dirname "$MODELS_DIR")/.staging`, on the same
filesystem as the destination, so the verified directory is renamed into place
rather than copied a second time:

```
rm -rf   $dest.partial
mv       $staged/model  →  $dest.partial
cp       manifest       →  $dest.partial/.almanac-manifest.json
write    bundle name    →  $dest.partial/.almanac-bundle
rm -rf   $dest
mv       $dest.partial  →  $dest
```

Lemonade scans `$MODELS_DIR` recursively and may do so at any moment, including
mid-import. It never sees a half-written model directory, because the directory
does not exist under its final name until it is complete.

The steps are chained with `&&` rather than left to `errexit`: `import_one` is
called as the condition of an `if`, and errexit does not apply inside a function
called that way. Without the explicit chain a failed `mv` would fall through to
reporting a successful import.

## 5. Identity, not names

`amf` names bundles content-addressedly:
`<org>__<repo>__<variant>__<digest12>`. `almanac-models` strips the digest for
the destination, so `<org>__<repo>__<variant>` is the installed name and two
revisions of the same variant collide by construction.

That collision is the feature. The `.almanac-bundle` marker records the *full*
source name including the digest, which makes the "already imported?" test an
identity check rather than a name match:

- marker matches the incoming bundle → already installed, skip, no copy;
- marker differs → a different revision wants the same path. Reported, refused,
  and `ALMANAC_FORCE=1` to replace.

Silently swapping one revision of a model for another is exactly the change an
operator most needs to be told about, and exactly the one a name-only check
cannot see.

## 6. `/var`, and why tmpfiles.d

`/var/lib/almanac/models` is created by
`/usr/lib/tmpfiles.d/almanac-models.conf`, not by the image build.

`/var` is not part of a bootc image. Contents shipped there are image state that
`bootc container lint` polices and that a deployment may not preserve as
expected. Creating the directory at boot puts it on the right side of that line,
and it also means an import can be the first thing that happens on a freshly
deployed image without a chicken-and-egg problem. The script calls `mkdir -p`
anyway rather than trusting it.

The directory is world-readable because `lemond` runs as the unprivileged
`lemonade` user and has to scan and `mmap` what was imported. Imported trees get
`chmod -R a+rX` and a `restorecon` where available, for the same reason.

## 7. Wiring Lemonade without owning its files

`lemond` seeds a fresh `config.json` from baked-in defaults, merges
`/usr/share/lemonade/defaults.json`, then merges whatever `LEMONADE_DEFAULTS_PATH`
names.

The obvious place to set `extra_models_dir` is that first defaults file — and it
is the wrong one. The lemonade package installs its complete release defaults
there, so writing our two-line version would discard every one of them. The
`LEMONADE_DEFAULTS_PATH` hook exists precisely as the seam for distro overrides,
so AlmanacOS uses it, via an `/etc/lemonade/conf.d` drop-in the unit already
globs, pointing at `/usr/share/almanac/lemonade-defaults.json`.

These are *defaults*: a value already in `/var/lib/lemonade/config.json` wins.
That is why import prints the `lemonade config set` line rather than assuming
the wiring took.

## 8. Privilege

The script asks for root only when the destination is not already writable.
`NEED_PRIV` is cleared when the nearest existing ancestor of `$MODELS_DIR` is
writable by the caller, so an operator who pointed `ALMANAC_MODELS_DIR` at a
directory they own is never prompted for a password to write to it.

Escalation prefers `run0` and falls back to `sudo`; with neither, it dies rather
than trying to continue in a way that would half-work.

## 9. Known limits

Stated rather than buried.

- **The trust root has to be carried in by hand.** Nothing in this design fixes
  the problem of the first key. If someone hands you a drive with both the
  bundles and the public key on it, the signature check proves nothing and the
  script cannot tell.
- **`ALMANAC_ALLOW_UNSIGNED=1` is a real hole**, offered because refusing
  outright would push people toward `cp -r` instead, which checks nothing at all
  and leaves no trace that it checked nothing.
- **Installed models cannot be re-verified in place.** Promotion moves the
  bundle's `model/` directory and keeps the manifest as
  `.almanac-manifest.json`, but `evidence/` and `manifest.json.minisig` are not
  retained, so `amf verify` cannot be pointed at an installed model. Re-verifying
  means re-running it against the drive.
- **There is no removal command.** Uninstalling a model is
  `rm -rf /var/lib/almanac/models/<name>` as root, followed by a `lemond`
  restart.
- **The drive is never unmounted** — that is the desktop's job, and guessing
  wrong about it is worse than leaving it.
- **The producer side refuses FAT32** (GGUF files routinely exceed its 4 GiB
  per-file ceiling), which means a drive prepared on Windows without reformatting
  will fail at `amf fetch` time, on the networked machine, not here.
