#!/bin/bash
# Snapshot the built firmware (.uf2) into zmk-config/backup/firm_NN/ along with
# the git revision it was built from.
#
# Source and config live in git; this captures only the binaries (which git
# ignores on purpose). The INFO.txt ties each backup back to a commit/tag so you
# always know which firmware is which, and can rebuild it from git if needed.
#
# Usage:  ./backup_firmware.sh        # back up the current zmk/app/build/*.uf2
# Build first:  (cd zmk-config && make)
set -e
cd "$(dirname "$0")"

BUILD="zmk/app/build"
BACKUP_DIR="zmk-config/backup"

shopt -s nullglob
uf2s=("$BUILD"/*.uf2)
if [ ${#uf2s[@]} -eq 0 ]; then
    echo "No .uf2 found in $BUILD."
    echo "Build first:  (cd zmk-config && make [left|right|devkit])"
    exit 1
fi

# Next firm_NN (continue the existing sequence).
n=0
for d in "$BACKUP_DIR"/firm_*/; do
    num=$(basename "$d" | sed 's/firm_//')
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    num=$((10#$num))        # force base-10 (firm_08/09 are not octal)
    (( num > n )) && n=$num
done
n=$((n + 1))
dir="$BACKUP_DIR/firm_$n"

mkdir -p "$dir"
cp -a "${uf2s[@]}" "$dir/"

# Record provenance.
desc=$(git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD)
dirty=""
[ -n "$(git status --porcelain)" ] && dirty=" (uncommitted changes present!)"
{
    echo "date:   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "git:    ${desc}${dirty}"
    echo "commit: $(git rev-parse HEAD)"
    echo ""
    echo "files:"
    for f in "$dir"/*.uf2; do
        printf "  %8d  %s\n" "$(stat -f%z "$f")" "$(basename "$f")"
    done
} > "$dir/INFO.txt"

echo "Backed up firmware -> $dir"
echo "----------------------------------------"
cat "$dir/INFO.txt"
