#!/bin/bash
# Finish setting up a fresh clone. Idempotent; safe to re-run.
#   1. fetch the submodules (zmk, zmk-config, zmk-modules/*) if
#      `git clone --recurse-submodules` was not used
#   2. symlink the local-only files (Makefile, *.zmk.yml) into zmk-config/,
#      because zmk-config's .gitignore excludes them
set -euo pipefail
cd "$(dirname "$0")"

git submodule update --init --recursive

for f in local/zmk-config/*; do
    dst="zmk-config/$(basename "$f")"
    [ -e "$dst" ] || [ -L "$dst" ] || ln -s "../$f" "$dst"
done

echo
echo "Done. Next:  ./0_setup.sh && ./1_start.sh && (cd zmk-config && make build)"
