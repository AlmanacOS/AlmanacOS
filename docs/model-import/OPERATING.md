# Importing models from a USB drive

**Applies to:** `ujust almanac-list-models`, `almanac-verify-models`,
`almanac-import-models`, `almanac-trust-model-key`
**Implemented by:** `system_files/usr/libexec/almanac-models`
**Recipes:** `system_files/usr/share/ublue-os/just/60-almanac.just`

This is the airgapped half of the model pipeline. The other half is
[`almanac-model-fetch`](https://github.com/AlmanacOS/almanac-model-fetch)
(`amf`), which runs on a networked machine. For why it is built this way, see
[DESIGN.md](DESIGN.md).

## The shape of it

```
  networked machine                 USB drive                AlmanacOS machine
  ─────────────────                 ─────────                ─────────────────
  amf fetch  ──────────────────▶   almanac/models/  ──────▶  ujust almanac-import-models
  downloads, hashes, captures       <org>__<repo>__          re-checks all of it offline,
  git evidence, signs               <variant>__<digest>/     installs for Lemonade
```

Nothing on the AlmanacOS side ever touches the network. Every claim a bundle
makes is re-checked from the bytes on the drive.

## Prerequisites

`amf` does the verifying; the `ujust` recipes are the operator interface around
it. It ships in the image — `build.sh` installs `almanac-model-fetch` from the
AlmanacOS COPR — so on a current image there is nothing to install. If it is
missing the script says so and stops rather than importing unchecked.

You also need the **public half of the key the fetching machine signs with**,
and you need to have carried it here yourself. A key taken off the same drive as
the bundles vouches for nothing: whoever wrote the bundles could have written
the key.

## One-time: trust the fetcher's key

On the networked machine, when you first set `amf` up:

```bash
amf keygen --secret amf.key --public amf.pub
```

Carry `amf.pub` to the AlmanacOS machine — a different drive, a printout you
retype, `scp` before the machine was airgapped, anything but the model drive —
and install it:

```bash
ujust almanac-trust-model-key /path/to/amf.pub
```

It is checked for the minisign header, you are told what you are trusting and
why it matters, and it lands at `/etc/almanac/amf.pub`. Every future import is
checked against it.

## Every time

Plug the drive in and let the desktop mount it. All three recipes find it on
their own — they search `/run/media/*/*`, `/media/*/*` and `/mnt/*` for anything
containing `almanac/models/` — so the drive argument is optional and only needed
if two drives carry bundles or the mount point is somewhere unusual.

**See what is on the drive:**

```bash
ujust almanac-list-models
ujust almanac-list-models /run/media/clem/MODELS      # explicit
```

**Re-verify without installing anything:**

```bash
ujust almanac-verify-models
```

This writes nothing. It runs keyless if you have not installed a fetcher key,
warning about exactly what it therefore could not check. If you have obtained
the upstream host's commit-signing key out of band, pass it as the second
argument to check the captured commit signature too — which means naming the
drive explicitly, since the arguments are positional:

```bash
ujust almanac-verify-models /run/media/clem/MODELS hf-signing-key.asc
```

That argument is deliberately not picked up automatically. Passing it fails any
bundle whose host does not sign its commits at all, which is ModelScope's normal
state rather than a fault.

**Verify and install:**

```bash
ujust almanac-import-models
```

Each bundle is copied into a staging directory, verified *there*, and only then
promoted. You will see, per bundle, its size, the copy, the verification, where
it landed, and the name Lemonade will list it under. A bundle that fails
verification is deleted and never appears in the directory Lemonade scans; the
run continues with the rest and exits non-zero at the end.

Afterwards you are offered a `lemond` restart, since that is when the new models
get picked up.

## Where things land

```
/var/lib/almanac/models/<org>__<repo>__<variant>/
├── <the model files>              the contents of the bundle's model/ directory
├── .almanac-manifest.json         the manifest that was verified
└── .almanac-bundle                the source bundle's content-addressed name
```

The `__<digest12>` suffix is dropped from the directory name, so two revisions of
the same variant land on the same path — that is a replacement, and it is
reported rather than silently accumulated.

Lemonade is pointed at `/var/lib/almanac/models` by
`/etc/lemonade/conf.d/20-almanac-models.conf` and scans it recursively for
`.gguf` files, listing what it finds under `extra.`. A bundle with one model file
is listed as `extra.<filename without .gguf>`; a shard set or a multimodal pair
is listed as `extra.<directory name>`.

On a machine where `lemond` wrote its `config.json` before this image existed,
the shipped default loses to the value already in that file. Set it once:

```bash
lemonade config set extra_models_dir=/var/lib/almanac/models
```

## When it does not work

| What you see | What it means |
| --- | --- |
| `No mounted drive carries almanac/models/.` | Nothing mounted has that directory. Let the desktop mount the drive, or pass the path. |
| `Several drives carry bundles; name the one you mean:` | Two candidates. Pass the one you want; it will not guess. |
| `No fetcher public key at /etc/almanac/amf.pub` | `ujust almanac-trust-model-key` has not been run. `verify` continues with a warning; `import` refuses. |
| `Refusing to import unverified bundles.` | Same cause. `ALMANAC_ALLOW_UNSIGNED=1` overrides it if you have decided the content hashes are enough. |
| `already holds a different revision of this model` | The destination has a different bundle's marker. `ALMANAC_FORCE=1` to replace it. |
| `needs 14 GiB, only 9 GiB free` | Space check, run before the copy. A GiB is kept in hand — filling the root filesystem of a bootc system is a worse day than a model that did not import. |
| `VERIFICATION FAILED — nothing was installed` | The staged copy did not check out. It has been deleted. Nothing reached Lemonade's directory. |
| `amf is not installed` | The image is missing `almanac-model-fetch`. Nothing is imported unchecked. |

## Environment

| Variable | Effect |
| --- | --- |
| `ALMANAC_ASSUME_YES=1` | Skip confirmation prompts |
| `ALMANAC_ALLOW_UNSIGNED=1` | Import without a trusted key — content hashes only |
| `ALMANAC_FORCE=1` | Replace an already-imported revision of a model |
| `ALMANAC_AMF_PUBKEY=PATH` | Use a different trusted key |
| `ALMANAC_MODELS_DIR=PATH` | Import somewhere other than `/var/lib/almanac/models` |

`ujust` passes the environment through, so these go in front of the command:

```bash
ALMANAC_FORCE=1 ujust almanac-import-models
```

Pointing `ALMANAC_MODELS_DIR` at a directory you own skips the privilege
escalation entirely — the script only asks for root when it actually needs it.

## Calling it directly

The recipes are thin wrappers. The script takes the same commands and is usable
outside the image, which is where it gets tested:

```bash
/usr/libexec/almanac-models list [drive]
/usr/libexec/almanac-models verify [drive] [upstream-key]
/usr/libexec/almanac-models import [drive]
/usr/libexec/almanac-models trust-key <path>
/usr/libexec/almanac-models --help
```
