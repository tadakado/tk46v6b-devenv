#!/bin/zsh
# Publish the firmware built here (with the local Zephyr / ZMK patches) as a
# GitHub Release of tk46v6b-devenv, so another Mac can flash it without a build
# environment -- over USB serial with flash_serial.sh (attached to the release),
# or via the UF2 drive where that is allowed.
#
# Assets: tk46v6_left/right and settings_reset as serial-DFU packages (-dfu.zip)
# and UF2s, flash_serial.sh, and INFO.txt (the exact revisions + patches used).
#
# Run it through make so the firmware is (re)built first:
#     make release          (make -B release after changing patches/ or zmk/,
#                            which the Makefile doesn't track)
# Needs: gh (logged in), adafruit-nrfutil.
# Refuses to publish uncommitted / unpushed sources; ALLOW_DIRTY=1 overrides.

set -e
cd "${0:A:h}"

REPO=tadakado/tk46v6b-devenv
BUILD=zmk/app/build

for c in gh adafruit-nrfutil; do
    command -v $c >/dev/null || { echo "$c not found" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in (gh auth login)" >&2; exit 1; }

# --- The firmware must be reproducible from what is on GitHub ----------------
problems=()
# Tracked changes (the patched zmk/ submodule shows as dirty content: ignored).
[[ -z "$(git status --porcelain --untracked-files=no --ignore-submodules=dirty)" ]] \
    || problems+=("devenv has uncommitted changes")
on_remote() { [[ -n "$(git -C "$1" branch -r --contains HEAD 2>/dev/null)" ]]; }
on_remote . || problems+=("devenv HEAD is not pushed")
for sub in zmk-config zmk-modules/*(/); do
    [[ -z "$(git -C $sub status --porcelain --untracked-files=no)" ]] \
        || problems+=("$sub has uncommitted changes")
    on_remote $sub || problems+=("$sub HEAD is not pushed")
done
./local_patches.sh check >/dev/null || problems+=("local patches are not all applied")
if (( ${#problems[@]} )); then
    print -l -- "Not releasing:" "  "${^problems} >&2
    [[ -n "$ALLOW_DIRTY" ]] || { echo "(ALLOW_DIRTY=1 to publish anyway)" >&2; exit 1; }
    echo "ALLOW_DIRTY set: publishing anyway" >&2
fi

# --- Collect the assets -------------------------------------------------------
rev=$(git rev-parse --short HEAD)
tag="fw-$(date +%Y%m%d)-$rev"
n=2; base=$tag
while gh release view "$tag" --repo $REPO >/dev/null 2>&1; do tag="$base-$n"; (( n++ )); done

out=firm/release/$tag
mkdir -p $out
for t in left:tk46v6_left right:tk46v6_right settings_reset:settings_reset; do
    dir=${t%%:*}; name=${t#*:}
    hex=$BUILD/$dir/zephyr/zmk.hex
    [[ -f $hex && -f $BUILD/$name.uf2 ]] || { echo "missing build output for $dir (run: make release)" >&2; exit 1; }
    adafruit-nrfutil dfu genpkg --dev-type 0x0052 --sd-req 0xFFFE --application $hex $out/$name-dfu.zip >/dev/null
    cp $BUILD/$name.uf2 $out/
done
cp flash_serial.sh $out/

{
    print "tk46v6b firmware $tag"
    print "Built $(date '+%F %T %Z') from tk46v6b-devenv $(git rev-parse HEAD)"
    print
    print "Submodules:"
    git submodule status | sed 's/^/  /'
    print
    print "Local patches applied:"
    for p in patches/zephyr/*.patch(N) patches/zmk/*.patch(N); do
        print "  $p  sha256:$(shasum -a 256 $p | cut -c1-12)"
    done
    print
    print "Flash over USB serial (no UF2 drive needed; pip3 install --user adafruit-nrfutil):"
    print "  ./flash_serial.sh left  tk46v6_left-dfu.zip     # only the left half plugged in"
    print "  ./flash_serial.sh right tk46v6_right-dfu.zip    # only the right half plugged in"
    print "  ./flash_serial.sh reset settings_reset-dfu.zip  # clears bonds/settings"
    print "Or copy the .uf2 to the XIAO's UF2 drive (double-tap RESET)."
} > $out/INFO.txt

echo ">>> $out:"; ls -1 $out | sed 's/^/    /'

gh release create "$tag" $out/* --repo $REPO --target "$(git rev-parse HEAD)" \
    --title "Firmware $tag" --notes-file $out/INFO.txt
echo ">>> released $tag"
