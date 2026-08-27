# AlmanacOS ujust manifest.
#
# ublue-os-just generates /usr/share/ublue-os/justfile when the RPM is built,
# with a hardcoded import list plus exactly one optional slot: 60-custom.just.
# Nothing globs the directory, so a file dropped beside the others is never
# read. AlmanacOS spends that one slot on a list of imports rather than on
# recipes, which keeps each concern in its own file.
#
# The imports are optional (`import?`) because `just check` runs
# `just --fmt --check` over every .just file in the repo, on a runner where
# /usr/share/ublue-os/just does not exist — a required import of an absent path
# is a parse error there. build.sh asserts each of these files is present in the
# image instead, so a typo fails the build rather than silently dropping recipes.

import? "/usr/share/ublue-os/just/60-almanac.just"
import? "/usr/share/ublue-os/just/61-almanac-devmode.just"
import? "/usr/share/ublue-os/just/62-almanac-ai.just"
