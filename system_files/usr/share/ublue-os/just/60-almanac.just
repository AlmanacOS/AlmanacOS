# AlmanacOS — memory tuning, offline model import, and the agent sandbox
#
# Installs to /usr/share/ublue-os/just/60-almanac.just
# Logic lives in /usr/libexec/almanac-memory, /usr/libexec/almanac-models and
# /usr/libexec/almanac-agentbox so it can be tested outside the image.

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

# List the coding agents the sandbox knows about, and which are in the image
[group('Almanac')]
almanac-list-agents:
    @/usr/libexec/almanac-agentbox --list

# Check the sandbox: krun runtime, /dev/kvm, guest image, available agents
[group('Almanac')]
almanac-agent-status:
    @/usr/libexec/almanac-agentbox status

# Pull the latest signed agent sandbox guest image
[group('Almanac')]
almanac-update-agent-sandbox:
    @/usr/libexec/almanac-agentbox update

# Store a credential for an agent, so sandboxes start authenticated
[group('Almanac')]
almanac-agent-login agent:
    @/usr/libexec/almanac-agentbox login "{{ agent }}"

# Forget an agent's stored credential (this does not revoke it upstream)
[group('Almanac')]
almanac-agent-logout agent:
    @/usr/libexec/almanac-agentbox logout "{{ agent }}"

# Show or edit the agent sandbox egress allowlist
[group('Almanac')]
almanac-agent-egress action="show" host="":
    @/usr/libexec/almanac-agentbox egress "{{ action }}" "{{ host }}"

# Check the agent sandbox still works (run this after an image update)
[group('Almanac')]
almanac-agent-selftest quick="":
    @/usr/libexec/almanac-agent-selftest "{{ quick }}"
