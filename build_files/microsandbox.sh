#!/bin/bash
#
# microsandbox prebuilt runtime.
#
# Not an RPM: upstream vendors a FORK of libkrunfw (superradcompany/libkrunfw,
# branch krunfw, pinned 5.6.1 / ABI 5) whose build compiles Linux 6.12.99 from
# source, and sdk/rust/build.rs downloads binaries at build time. Neither
# survives mock. So we consume their prebuilt bundle, verified upstream by
# `just bump-microsandbox` and pinned by digest in the Containerfile.
#
# CRITICAL: this bundle's libkrunfw.so.5 has the same soname as the one
# Fedora's libkrun pulls in for agentbox. They must never see each other.
# Hence a private libdir and an LD_LIBRARY_PATH wrapper — never /usr/lib64
# directly, never an ld.so.conf.d drop-in.

set -ouex pipefail

MSB_TARBALL="/ctx/microsandbox.tar.gz"
MSB_LIBEXEC="/usr/libexec/microsandbox"
MSB_LIBDIR="/usr/lib64/microsandbox"

extract_dir="$(mktemp -d)"
tar -xzf "$MSB_TARBALL" -C "$extract_dir"

install -d "$MSB_LIBEXEC" "$MSB_LIBDIR"

# Binaries: msb, plus msb-metrics when the bundle carries it.
for name in msb msb-metrics; do
    src="$(find "$extract_dir" -type f -name "$name" -print -quit)"
    [ -n "$src" ] || continue
    install -m 0755 "$src" "$MSB_LIBEXEC/$name"
done

[ -x "$MSB_LIBEXEC/msb" ] || { echo "msb not found in bundle"; exit 1; }

# Forked guest kernel library, into the private libdir with its soname chain.
libsrc="$(find "$extract_dir" -type f -name 'libkrunfw.so.*' -print -quit)"
[ -n "$libsrc" ] || { echo "libkrunfw not found in bundle"; exit 1; }
libname="$(basename "$libsrc")"
install -m 0755 "$libsrc" "$MSB_LIBDIR/$libname"

# libkrunfw.so.5.6.1 -> major 5
major="$(echo "$libname" | sed -E 's/^libkrunfw\.so\.([0-9]+).*/\1/')"
ln -sf "$libname" "$MSB_LIBDIR/libkrunfw.so.$major"
ln -sf "libkrunfw.so.$major" "$MSB_LIBDIR/libkrunfw.so"

# Wrapper. MSB_HOME is deliberately NOT set: upstream resolves it to
# ~/.microsandbox/ and also caches OCI images there, so pointing it at /usr
# would break `msb pull` on a read-only deployment.
cat > /usr/bin/msb <<'WRAPPER'
#!/bin/bash
exec env LD_LIBRARY_PATH="/usr/lib64/microsandbox${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    /usr/libexec/microsandbox/msb "$@"
WRAPPER
chmod 0755 /usr/bin/msb

if [ -x "$MSB_LIBEXEC/msb-metrics" ]; then
    sed 's|/msb "|/msb-metrics "|' /usr/bin/msb > /usr/bin/msb-metrics
    chmod 0755 /usr/bin/msb-metrics
fi

# Record what shipped, for support and for `just verify-microsandbox`.
grep -oP 'releases/download/v\K[0-9.]+' /ctx/Containerfile 2>/dev/null \
    > /usr/share/almanac/microsandbox-version || true

rm -rf "$extract_dir"
