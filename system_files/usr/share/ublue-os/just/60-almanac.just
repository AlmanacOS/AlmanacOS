# AlmanacOS — memory tuning
#
# Installs to /usr/share/ublue-os/just/60-almanac.just
# Logic lives in /usr/libexec/almanac-memory so it can be tested outside the image.

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

