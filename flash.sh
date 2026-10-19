#!/bin/zsh
# Enter the XIAO's UF2 bootloader (1200bps touch on its board_cdc_acm_uart
# watcher port -- see zmk-bootloader-1200). No RESET button press needed.
#
# Multiple /dev/tty.usbmodem* ports may be present (the XIAO alone exposes
# 3; other USB-serial gadgets, e.g. a sniffer dongle, may add more). A single
# board's ports share a numeric prefix, so: group ports by prefix, and if
# exactly one prefix has more than one port (an unrelated single-port device
# doesn't), that's the board -- touch its lowest-numbered port.
#
# Then waits (up to FLASH_WAIT seconds, default 20) for the UF2 bootloader
# drive to mount, so `./flash.sh && make flash_left` works in one go.
#
# Usage: ./flash.sh            (or FLASH_WAIT=30 ./flash.sh)

set -e

FLASH_WAIT=${FLASH_WAIT:-20}

# Wait for a mounted UF2 drive (identified by INFO_UF2.TXT).
wait_uf2() {
    local i=0 vols
    while :; do
        vols=(/Volumes/*/INFO_UF2.TXT(N))
        if (( ${#vols[@]} > 0 )); then
            echo ">>> UF2 drive ready: ${vols[1]:h}"
            return 0
        fi
        if (( i >= FLASH_WAIT * 2 )); then
            echo "no UF2 bootloader drive mounted after ${FLASH_WAIT}s" >&2
            return 1
        fi
        (( i == 0 )) && echo ">>> waiting for the UF2 bootloader drive (up to ${FLASH_WAIT}s)..."
        (( i++ )) || true
        sleep 0.5
    done
}

ports=(/dev/tty.usbmodem*(N))
if (( ${#ports[@]} == 0 )); then
    echo "no /dev/tty.usbmodem* ports found" >&2
    exit 1
fi

if (( ${#ports[@]} == 1 )); then
    port=$ports[1]
    echo ">>> touching $port at 1200bps to enter bootloader"
    stty -f "$port" 1200
    wait_uf2
    exit $?
fi

typeset -A count_by_prefix
for p in $ports; do
    num=${p##*usbmodem}
    prefix=${num[1,-3]}
    count_by_prefix[$prefix]=$(( ${count_by_prefix[$prefix]:-0} + 1 ))
done

board_prefixes=()
for prefix in ${(k)count_by_prefix}; do
    (( count_by_prefix[$prefix] > 1 )) && board_prefixes+=($prefix)
done

if (( ${#board_prefixes[@]} != 1 )); then
    echo "can't tell which board to flash (ports: $ports)" >&2
    exit 1
fi

port=$(print -l -- $ports | grep "usbmodem${board_prefixes[1]}" | sort | head -1)
echo ">>> touching $port at 1200bps to enter bootloader"
stty -f "$port" 1200
wait_uf2
