#!/bin/bash
# Recreate the local ZMK build workspace next to this script:
#   zmk/          upstream ZMK, pinned to ZMK_REV
#   zmk-config/   github.com/tadakado/tk46v6b
#   zmk-modules/  the five out-of-tree modules
# Safe to re-run: existing clones are left untouched.
set -euo pipefail
cd "$(dirname "$0")"

GH="https://github.com/tadakado"
ZMK_URL="https://github.com/zmkfirmware/zmk.git"
ZMK_REV="773dec58eaacaef4703b3e4595e50bd71f6cad3d"   # v0.3-138-g773dec58
MODULES=(zmk-ir zmk-rgb-indicator zmk-ble-debug zmk-bootloader-1200 zmk-ble-mouse-host)

clone() {  # clone <url> <dir>
    if [ -d "$2/.git" ]; then echo "skip: $2 (already cloned)"; else git clone "$1" "$2"; fi
}

clone "$ZMK_URL" zmk
git -C zmk checkout --quiet "$ZMK_REV"

clone "$GH/tk46v6b.git" zmk-config

mkdir -p zmk-modules
for m in "${MODULES[@]}"; do clone "$GH/$m.git" "zmk-modules/$m"; done

# Local-only files that zmk-config's .gitignore excludes (Makefile, *.zmk.yml):
# symlink them in so `make` works from zmk-config/.
for f in local/zmk-config/*; do
    dst="zmk-config/$(basename "$f")"
    [ -e "$dst" ] || [ -L "$dst" ] || ln -s "../$f" "$dst"
done

echo
echo "Done. Next:  ./0_setup.sh && ./1_start.sh && (cd zmk-config && make build)"
