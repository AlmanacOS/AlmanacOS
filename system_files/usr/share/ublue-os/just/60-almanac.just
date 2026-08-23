# AlmanacOS — memory tuning and offline model import
#
# Installs to /usr/share/ublue-os/just/60-almanac.just
# Logic lives in /usr/libexec/almanac-memory and /usr/libexec/almanac-models so
# it can be tested outside the image.

# Show GPU topology and the current TTM system-memory cap
[group('Almanac')]
almanac-show-memory:
    @/usr/libexec/almanac-memory show

# Propose and apply a TTM system-memory cap (unified-memory APUs only)
[group('Almanac')]
almanac-tune-memory percent="75":
    @/usr/libexec/almanac-memory tune {{ percent }}

# Remove the ttm.pages_limit kernel argument, returning to the kernel default
[group('Almanac')]
almanac-reset-memory:
    @/usr/libexec/almanac-memory reset

# List the model bundles on a USB drive (leave drive empty to auto-detect)
[group('Almanac')]
almanac-list-models drive="":
    @/usr/libexec/almanac-models list "{{ drive }}"

# Re-verify every bundle on a drive, offline. Writes nothing.
[group('Almanac')]
almanac-verify-models drive="" upstream_key="":
    @/usr/libexec/almanac-models verify "{{ drive }}" "{{ upstream_key }}"

# Verify and import models from a USB drive into Lemonade's model directory
[group('Almanac')]
almanac-import-models drive="":
    @/usr/libexec/almanac-models import "{{ drive }}"

# Install the fetching machine's public key, which imports are verified against
[group('Almanac')]
almanac-trust-model-key keyfile:
    @/usr/libexec/almanac-models trust-key "{{ keyfile }}"
