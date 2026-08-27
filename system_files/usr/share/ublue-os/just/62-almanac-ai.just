# AlmanacOS — terminal AI agents, and which model server they talk to.
#
# Installs to /usr/share/ublue-os/just/62-almanac-ai.just and is reached through
# the import manifest in 60-custom.just.
#
# Logic lives in /usr/libexec/almanac-ai so it can be tested outside the image.

# Choose and install terminal AI agents
[group('Almanac')]
ai:
    @/usr/libexec/almanac-ai menu

# Point AI clients at a local model server: lemonade, ramalama, or auto
[group('Almanac')]
almanac-ai-backend which="auto":
    @/usr/libexec/almanac-ai backend "{{ which }}"
