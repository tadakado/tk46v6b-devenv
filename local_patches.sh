#!/bin/zsh
# Apply / revert the local patches to trees this repo does not own:
#   patches/zephyr/*.patch -> Zephyr inside the zmk-dev container
#                             (/workspaces/zmk/zephyr, the zmk-zephyr docker volume,
#                             fetched by `west update`)
#   patches/zmk/*.patch    -> the zmk/ submodule (shows as modified in git status)
# Local builds only: GitHub Actions builds use pristine upstream sources.
#
# Usage: ./local_patches.sh apply | revert | status | check
#   check: exit 1 unless every patch is applied (used by make check_env)
#
# After apply/revert, force a rebuild (these trees are not make dependencies):
#   make -B left

set -u
cd "${0:A:h}"
C=zmk-dev

zgit() { docker exec -i -w /workspaces/zmk/zephyr $C git "$@"; }   # Zephyr (container)
kgit() { git -C zmk "$@"; }                                        # ZMK (host submodule)

patches=(patches/zephyr/*.patch(N) patches/zmk/*.patch(N))
(( ${#patches} )) || { echo "no patches" >&2; exit 1; }
if [[ -n ${(M)patches:#patches/zephyr/*} ]] && ! docker inspect $C >/dev/null 2>&1; then
    echo "container $C not running (./1_start.sh)" >&2; exit 1
fi

rc=0
for p in $patches; do
    case $p in patches/zephyr/*) g=zgit ;; *) g=kgit ;; esac
    if $g apply --check -R - < "$p" 2>/dev/null; then state=applied
    elif $g apply --check - < "$p" 2>/dev/null; then state=not-applied
    else state=CONFLICT; fi
    case "${1:-status}" in
        status) echo "$state  $p" ;;
        check)
            if [[ $state != applied ]]; then echo "patch not applied ($state): $p" >&2; rc=1; fi ;;
        apply)
            if [[ $state == not-applied ]]; then $g apply - < "$p" && echo "applied  $p"
            else echo "skip ($state)  $p"; fi ;;
        revert)
            if [[ $state == applied ]]; then $g apply -R - < "$p" && echo "reverted $p"
            else echo "skip ($state)  $p"; fi ;;
        *) echo "usage: $0 apply | revert | status | check" >&2; exit 1 ;;
    esac
done
exit $rc
