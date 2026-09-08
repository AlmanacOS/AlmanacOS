# >>> microsandbox pin — managed by `just bump-microsandbox`, do not hand-edit.
# The digest is written only after `gh release verify-asset` validates the
# GitHub release attestation (release↔tag↔asset binding, NOT build provenance).
ARG MSB_VERSION="0.6.17"
ARG MSB_SHA256="e4b0a4473b2ecb1ef14cfcde33b2cf35a62b81c611517215848f9179f06fd045"

# Add homebrew
ARG BREW_IMAGE="ghcr.io/ublue-os/brew:latest"
FROM ${BREW_IMAGE} AS brew
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY --from=brew /system_files /system_files
COPY build_files /
COPY system_files /system_files

# microsandbox tarball, pinned by the ARGs at the top of this file. The digest
# is NOT enforced here: buildah's ADD accepts only --chmod and --chown, so
# `--checksum=` fails the build. microsandbox.sh checks MSB_SHA256 before it
# extracts anything, which is the only point where the bytes are used.
ARG MSB_VERSION
ADD https://github.com/superradcompany/microsandbox/releases/download/v${MSB_VERSION}/microsandbox-linux-x86_64.tar.gz /microsandbox.tar.gz

# Base Image
FROM ghcr.io/ublue-os/kinoite-main:latest
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

ARG MSB_VERSION
ARG MSB_SHA256
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    MSB_VERSION="${MSB_VERSION}" MSB_SHA256="${MSB_SHA256}" \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
