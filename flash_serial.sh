#!/bin/zsh
# Flash ZMK firmware to the XIAO nRF52840 entirely over USB serial (no UF2 drive),
# for Macs where USB mass storage is blocked.
#
#   1. Take a serial-DFU package (.zip), or wrap a .hex into one
#      (adafruit-nrfutil dfu genpkg).
#   2. 1200bps touch on the board's first CDC port (zmk-bootloader-1200), which
#      reboots it into the Adafruit bootloader, the same as flash.sh.
#   3. Wait for the bootloader's CDC port and run serial DFU on it.
#
# Works on its own (no build environment needed), e.g. on another Mac with a
# package downloaded from this repo's GitHub Releases (see release_firmware.sh).
#
# Needs adafruit-nrfutil:  pip3 install --user adafruit-nrfutil
#   (or: pipx install adafruit-nrfutil)
#
# Usage: ./flash_serial.sh [left|right|devkit|reset] FILE.zip|FILE.hex
#   The side picks which plugged-in board to flash (see below). Without it, it is
#   guessed from the file name: *right* -> right, *settings_reset* -> reset,
#   anything else -> left.
#   FLASH_WAIT=30 ./flash_serial.sh ...   to wait longer for the bootloader.

set -e

FLASH_WAIT=${FLASH_WAIT:-20}

side=""
case "$1" in
    left|right|devkit|reset) side=$1; shift ;;
esac
file=$1

if [[ -z "$file" || ! -f "$file" ]]; then
    echo "usage: $0 [left|right|devkit|reset] FILE.zip|FILE.hex" >&2
    exit 1
fi
if [[ -z "$side" ]]; then
    case "${file:t}:$file" in
        *settings_reset*) side=reset ;;
        *right*)          side=right ;;
        *)                side=left ;;
    esac
fi
if ! command -v adafruit-nrfutil >/dev/null; then
    echo "adafruit-nrfutil not found. Install it with: pip3 install --user adafruit-nrfutil" >&2
    echo "(and make sure its bin dir, e.g. ~/Library/Python/3.x/bin, is on PATH)" >&2
    exit 1
fi

case "$file" in
    *.zip) pkg=$file ;;
    *.hex)
        pkg="${file:r}-dfu.zip"
        echo ">>> packaging $file -> $pkg"
        # 0x0052: nRF52 device type; 0xFFFE: don't check the SoftDevice version.
        adafruit-nrfutil dfu genpkg --dev-type 0x0052 --sd-req 0xFFFE --application "$file" "$pkg" >/dev/null
        ;;
    *) echo "expected a .zip (DFU package) or .hex: $file" >&2; exit 1 ;;
esac
echo ">>> target: $side half ($pkg)"

# Find the target board's port prefix (a board's ports share a numeric prefix).
# Running ZMK, the left half / devkit expose 3 CDC ports (bootloader watcher,
# Studio, log) while the right half exposes only the watcher -- so is a board
# running settings_reset. Use that to avoid putting one half's firmware on the
# other when both are plugged in:
#   right:  needs a single-port board
#   left / devkit:  prefers a multi-port board; a lone single-port board is
#           accepted with a warning (e.g. the left half after settings_reset)
#   settings_reset:  needs exactly one board plugged in
case $side in
    right) want=single ;;
    reset) want=only ;;
    *)     want=multi ;;
esac

ports_all=(/dev/cu.usbmodem*(N))
typeset -A count
for p in $ports_all; do
    num=${p##*usbmodem}
    count[${num[1,-3]}]=$(( ${count[${num[1,-3]}]:-0} + 1 ))
done
found=()
for k in ${(k)count}; do
    case $want in
        single) (( count[$k] == 1 )) && found+=($k) ;;
        multi)  (( count[$k] > 1 )) && found+=($k) ;;
        only)   found+=($k) ;;
    esac
done
if [[ $want == multi && ${#found[@]} -eq 0 && ${#count[@]} -eq 1 ]]; then
    found=(${(k)count})
    echo "WARNING: the only board has a single serial port (not running the full firmware?);" >&2
    echo "         flashing it anyway -- make sure it is the half you mean." >&2
fi
if (( ${#found[@]} != 1 )); then
    echo "can't tell which board to flash (ports: $ports_all)" >&2
    case $want in
        single) echo "Plug in the right half alone (no other single-port USB serial device)." >&2 ;;
        only)   echo "Plug in only the board to reset." >&2 ;;
        multi)  echo "Plug in only the left half (or devkit)." >&2 ;;
    esac
    exit 1
fi
prefix=$found[1]
touch_port=$(print -l -- /dev/cu.usbmodem${prefix}*(N) | sort | head -1)

echo ">>> touching $touch_port at 1200bps to enter the bootloader"
stty -f "$touch_port" 1200 || true

# The application's ports go away (the touched one with them), then the
# bootloader comes up with a single CDC port under the same prefix -- possibly
# with the same name as the touched one, so wait for it to vanish first.
echo ">>> waiting for the bootloader's serial port (up to ${FLASH_WAIT}s)..."
i=0; gone=0; bl=""
while (( i < FLASH_WAIT * 4 )); do
    if (( ! gone )); then
        [[ -e "$touch_port" ]] || gone=1
    else
        ports=(/dev/cu.usbmodem${prefix}*(N))
        (( ${#ports[@]} >= 1 )) && { bl=$ports[1]; break; }
    fi
    sleep 0.25; (( i++ )) || true
done
if [[ -z "$bl" ]]; then
    echo "bootloader serial port did not appear" >&2
    exit 1
fi
sleep 0.5   # let the CDC port settle before opening it

echo ">>> serial DFU on $bl"
adafruit-nrfutil --verbose dfu serial --package "$pkg" -p "$bl" -b 115200 --singlebank
echo ">>> done; the board restarts into the new firmware"
