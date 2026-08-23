#!/bin/bash
#
# microsandbox prebuilt runtime.
#
# Not an RPM: upstream vendors a FORK of libkrunfw (superradcompany/libkrunfw,
# branch krunfw, pinned 5.6.1 / ABI 5) whose build compiles Linux 6.12.99 from
# source, and sdk/rust/build.rs downloads binaries at build time. Neither
# survives mock. So we consume their prebuilt bundle, verified upstream by
# `just bump-microsandbox` (GitHub release attestation) and pinned by digest
# in the Containerfile.
#
# CRITICAL — how msb finds libkrunfw:
# It does NOT dlopen by soname via ld.so. It runs its own path search:
#   1. <realpath of exe>/libkrunfw.so.<ver>
#   2. <exe dir>/../lib/libkrunfw.so.<ver>
#   3. $MSB_HOME/lib/libkrunfw.so.<ver>
# So the fork is installed BESIDE the binary in /usr/libexec/microsandbox.
# That keeps it out of /usr/lib64 and out of the ld.so cache entirely, so the
# fork can never shadow a packaged libkrunfw if one is ever layered in.
# LD_LIBRARY_PATH and ld.so.conf.d drop-ins are both wrong here — the first
# has no effect, the second creates the collision we're avoiding.
#
# MSB_HOME is deliberately NOT set: upstream resolves it to ~/.microsandbox/
# and caches OCI images there, so pointing it at /usr breaks `msb pull` on a
# read-only deployment.

set -ouex pipefail

MSB_TARBALL="/ctx/microsandbox.tar.gz"
MSB_LIBEXEC="/usr/libexec/microsandbox"

extract_dir="$(mktemp -d)"
tar -xzf "$MSB_TARBALL" -C "$extract_dir"

install -d "$MSB_LIBEXEC"

# Binaries: msb, plus msb-metrics when the bundle carries it.
for name in msb msb-metrics; do
    src="$(find "$extract_dir" -type f -name "$name" -print -quit)"
    [ -n "$src" ] || continue
    install -m 0755 "$src" "$MSB_LIBEXEC/$name"
done

[ -x "$MSB_LIBEXEC/msb" ] || { echo "ERROR: msb not found in bundle" >&2; exit 1; }

# Forked guest kernel library, beside the binary (search path 1 above).
libsrc="$(find "$extract_dir" -type f -name 'libkrunfw.so.*' -print -quit)"
[ -n "$libsrc" ] || { echo "ERROR: libkrunfw not found in bundle" >&2; exit 1; }
libname="$(basename "$libsrc")"
install -m 0755 "$libsrc" "$MSB_LIBEXEC/$libname"

# libkrunfw.so.5.6.1 -> major 5, for anything that does look by soname.
major="$(echo "$libname" | sed -E 's/^libkrunfw\.so\.([0-9]+).*/\1/')"
ln -sf "$libname" "$MSB_LIBEXEC/libkrunfw.so.$major"
ln -sf "libkrunfw.so.$major" "$MSB_LIBEXEC/libkrunfw.so"

# Plain symlinks into PATH. Rust's current_exe() reads /proc/self/exe, which
# resolves to the real path in MSB_LIBEXEC, so search path 1 hits. No wrapper.
ln -sf "$MSB_LIBEXEC/msb" /usr/bin/msb
if [ -x "$MSB_LIBEXEC/msb-metrics" ]; then
    ln -sf "$MSB_LIBEXEC/msb-metrics" /usr/bin/msb-metrics
fi

# Record what shipped, for support and for `just verify-microsandbox`.
# MSB_VERSION can be passed through from the Containerfile; otherwise fall
# back to asking the binary, and never fail the build over a version string.
install -d /usr/share/almanac
version="${MSB_VERSION:-}"
if [ -z "$version" ]; then
    version="$("$MSB_LIBEXEC/msb" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
fi
echo "${version:-unknown}" > /usr/share/almanac/microsandbox-version
echo "$libname" > /usr/share/almanac/microsandbox-libkrunfw

# Build-time assertion. A version bump that changes the libkrunfw filename or
# moves the binary must fail HERE, not at first run on a user's machine.
[ -f "$MSB_LIBEXEC/libkrunfw.so.5.6.1" ] || {
    echo "ERROR: expected libkrunfw.so.5.6.1 beside msb, found '$libname'." >&2
    echo "       Upstream changed the pinned libkrunfw — re-check msb's" >&2
    echo "       search paths and update this assertion." >&2
    exit 1
}
[ -L /usr/bin/msb ] || { echo "ERROR: /usr/bin/msb symlink missing" >&2; exit 1; }

rm -rf "$extract_dir"
