# Terminal coding agents that talk to a vendor's cloud. Each needs an account
# and an API key, and each sends your code to that vendor. They are here because
# they are useful, not because they fit the rest of this image — nothing
# installs them unless you pick them in `ujust ai`.
#
# Derived from Bluefin (Apache-2.0, like AlmanacOS):
#   projectbluefin/common,
#   system_files/shared/usr/share/ublue-os/homebrew/ai-tools.Brewfile
#   commit 4630fb2be2126e07df0d26433462019c76cec3a6
#
# Upstream's desktop entries are dropped: `cask "ublue-os/tap/lm-studio-linux"`
# is proprietary, and `flatpak "ai.jan.Jan"` duplicates Alpaca, which AlmanacOS
# already preinstalls (system_files/usr/share/flatpak/preinstall.d).

tap "ublue-os/tap", trusted: true

brew "kimi-code"
brew "mistral-vibe"
brew "qwen-code"
cask "claude-code"
cask "codex"
cask "copilot-cli"
brew "gemini-cli"
