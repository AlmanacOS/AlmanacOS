# Kubernetes tooling, installed by `ujust devmode`.
#
# Copied from Bluefin (Apache-2.0, like AlmanacOS):
#   projectbluefin/common,
#   system_files/shared/usr/share/ublue-os/homebrew/k8s-tools.Brewfile
#   commit 25b3e1e7c602f70695c6087b39cc2f679e0a6c09
# One edit: `trusted: true` on each tap. Homebrew 6 refuses to load a formula
# from a non-official tap unless the tap is in the trust store, and `brew
# bundle` only trusts the taps a Brewfile marks. Without it every line below
# that names a tap fails with `Refusing to load formula ... from untrusted tap`.

tap "buildpacks/tap", trusted: true
brew "buildpacks/tap/pack"
tap "k0sproject/tap", trusted: true
brew "k0sproject/tap/k0sctl"
brew "cdk8s"
brew "dagger"
brew "grype"
brew "helm"
brew "k3sup"
brew "k9s"
brew "kind"
brew "kubectl"
brew "kubectx"
brew "rancher-cli"
brew "rancher-machine"
brew "syft"
