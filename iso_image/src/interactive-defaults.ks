# Appended to /usr/share/anaconda/interactive-defaults.ks in the live image.
#
# These are defaults for an interactive install, not an unattended one: the user
# still picks the disk and creates their account in the Web UI. This only
# answers "install what, from where".
#
# --transport=containers-storage is the airgap-critical part. The payload was
# pulled into the live rootfs's container storage at image build time, so the
# install reads it from the ISO and never opens a socket. On a machine with no
# network — which is what AlmanacOS is built for — a registry transport here
# would mean the ISO cannot install the OS it is an ISO of.
#
# --no-signature-verification because the payload is being read out of local
# container storage where it arrived already verified: it was pulled at build
# time, over the network, against the registry's own guarantees. There is no
# second check available at install time that would mean anything, and asking
# for one that cannot be satisfied would only fail the install.

ostreecontainer --url=@PAYLOAD_IMAGE@ --transport=containers-storage --no-signature-verification

# Point the installed system at the registry for updates.
#
# Not optional. The install above read the payload out of the ISO's container
# storage, and ostree records that as the deployment's origin — so a freshly
# installed machine believes its upstream is a container store that only ever
# existed on the ISO. `bootc upgrade` on such a system has nowhere to look. This
# rewrites the origin to the registry the image is actually published to.
#
# The reference is left unverified, which is the same posture the system has
# today and is *not* the right long-term answer: these images are cosign-signed
# by CI and the public key already ships at /etc/pki/containers/almanacos.pub.
# Turning that on is two changes — `ostree-image-signed:docker://` here, and a
# sigstoreSigned entry for this repository merged into
# /etc/containers/policy.json by build_files/build.sh. It is left out
# deliberately: a policy that rejects the base
# image breaks `bootc upgrade` on every machine that has already deployed the
# image carrying that policy, and recovering means a rollback. That is a change
# worth making on purpose, with a test machine, rather than as a side effect of
# wiring up ISO builds.
%post --erroronfail --log=/tmp/almanac-origin-rewrite.log
set -x
sed -i \
    's|^container-image-reference=.*|container-image-reference=ostree-unverified-registry:@PAYLOAD_IMAGE@|' \
    /ostree/deploy/default/deploy/*.origin
%end
