# AlmanacOS — developer tooling, installed on demand.
#
# Installs to /usr/share/ublue-os/just/61-almanac-devmode.just and is reached
# through the import manifest in 60-custom.just.
#
# Logic lives in /usr/libexec/almanac-devmode so it can be tested outside the
# image. The recipes named here are the ones Bluefin users will look for.

# Choose and install developer tooling: containers, VMs, IDEs, Kubernetes
[group('Almanac')]
devmode:
    @/usr/libexec/almanac-devmode menu

# Add the current user to the developer groups, without the install menu
[group('Almanac')]
dx-group:
    @/usr/libexec/almanac-devmode groups

# Report whether the hosts `ujust devmode` installs from are reachable
[group('Almanac')]
devmode-preflight:
    @/usr/libexec/almanac-devmode preflight
