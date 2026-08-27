# Terminal AI agents that speak the OpenAI HTTP API, and so can be pointed at
# lemonade or ramalama with `ujust almanac-ai-backend`. None of them requires a
# vendor account to be useful on this image.
#
# Derived from Bluefin (Apache-2.0, like AlmanacOS):
#   projectbluefin/common,
#   system_files/shared/usr/share/ublue-os/homebrew/ai-tools.Brewfile
#   commit 4630fb2be2126e07df0d26433462019c76cec3a6
#
# Two edits from upstream:
#
#   `brew "ramalama"` is deliberately absent. AlmanacOS installs ramalama as an
#   RPM (build_files/build.sh) so an offline machine has it at first boot.
#   Homebrew's prefix precedes /usr/bin on PATH, so adding it back here would
#   silently shadow the packaged copy with one that lags it.
#
#   `aichat` is added, which upstream dropped. It is the best fit here: a small
#   client with first-class support for an arbitrary OpenAI-compatible base URL.

tap "anomalyco/tap"
tap "charmbracelet/tap"
tap "ublue-os/tap", trusted: true

brew "aichat"
brew "anomalyco/tap/opencode"
brew "block-goose-cli"
brew "charmbracelet/tap/crush"
brew "llm"
brew "ublue-os/tap/linux-mcp-server"
