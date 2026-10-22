#!/bin/zsh
# Apply / revert the local Zephyr patches in patches/zephyr/ to the Zephyr tree
# inside the zmk-dev container (/workspaces/zmk/zephyr, a docker volume fetched
# by `west update` -- not part of this repo). Local builds only: the GitHub
# Actions build fetches pristine Zephyr. `west update` may undo it; re-run
# `./zephyr_patch.sh status` after one.
#
# Usage: ./zephyr_patch.sh apply | revert | status | check
#   check: exit 1 unless every patch is applied (used by make check_env)
#
# After apply/revert, force a rebuild (Zephyr is not a make dependency):
#   make -B left

set -u
cd "${0:A:h}"
C=zmk-dev
Z=/workspaces/zmk/zephyr
patches=(patches/zephyr/*.patch(N))

dgit() { docker exec -i -w $Z $C git "$@"; }

docker inspect $C >/dev/null 2>&1 || { echo "container $C not running (./1_start.sh)" >&2; exit 1; }
(( ${#patches} )) || { echo "no patches in patches/zephyr" >&2; exit 1; }

rc=0
for p in $patches; do
    if dgit apply --check -R - < "$p" 2>/dev/null; then state=applied
    elif dgit apply --check - < "$p" 2>/dev/null; then state=not-applied
    else state=CONFLICT; fi
    case "${1:-status}" in
        status) echo "$state  $p" ;;
        check)
            if [[ $state != applied ]]; then echo "Zephyr patch not applied ($state): $p" >&2; rc=1; fi ;;
        apply)
            if [[ $state == not-applied ]]; then dgit apply - < "$p" && echo "applied  $p"
            else echo "skip ($state)  $p"; fi ;;
        revert)
            if [[ $state == applied ]]; then dgit apply -R - < "$p" && echo "reverted $p"
            else echo "skip ($state)  $p"; fi ;;
        *) echo "usage: $0 apply | revert | status | check" >&2; exit 1 ;;
    esac
done
exit $rc
