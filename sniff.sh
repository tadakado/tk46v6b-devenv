#!/bin/zsh
# nRF Sniffer for Bluetooth LE helper (macOS, Wireshark + nRF Sniffer extcap).
#
#   ./sniff.sh probe        Dump tshark / extcap / nrfutil info to
#                           logs/sniff-probe.txt.
#   ./sniff.sh flash-dongle Program the nRF Sniffer firmware onto an nRF52840
#                           Dongle (PCA10059) with nrfutil (needs the sniffer
#                           .hex from the nRF Sniffer package).
#   ./sniff.sh capture      Follow the keyboard's host link with the SC LTK and
#                           record it to logs/sniff-*.pcap. The keyboard address
#                           and LTK are taken from the newest logs/console-*.log
#                           (ble_conn "local ..." line / bt_keys "SC LTK"), so
#                           run ./console.sh in another terminal. Stops by
#                           itself STOP_AFTER s (default 5) after the console
#                           logs a host disconnect with reason 0x24 (override
#                           with STOP_REASON), or on Ctrl-C.
#                           Overrides: SNIFF_PORT, KB_ADDR ("AA:..:FF random"), LTK.
#
# Output goes under logs/ (git-ignored).

set -u
cd "${0:A:h}"
mkdir -p logs

# --- locate tshark ---------------------------------------------------------
tshark=$(command -v tshark 2>/dev/null)
[[ -z "$tshark" && -x /Applications/Wireshark.app/Contents/MacOS/tshark ]] &&
    tshark=/Applications/Wireshark.app/Contents/MacOS/tshark
if [[ -z "$tshark" ]]; then
    echo "tshark not found (install Wireshark, or put tshark on PATH)" >&2
    exit 1
fi

# --- locate the nRF Sniffer extcap ----------------------------------------
find_extcap() {
    local dirs=() d f
    # Wireshark tells us its personal / global extcap folders.
    dirs+=("${(@f)$("$tshark" -G folders 2>/dev/null | awk -F'\t' '/[Ee]xtcap/ {print $2}')}")
    dirs+=(~/.local/lib/wireshark/extcap ~/.config/wireshark/extcap
           /Applications/Wireshark.app/Contents/MacOS/extcap
           /Applications/Wireshark.app/Contents/PlugIns/wireshark/extcap)
    for d in $dirs; do
        for f in "$d"/nrf_sniffer_ble.sh "$d"/nrf_sniffer_ble.py; do
            [[ -x "$f" ]] && { print -- "$f"; return 0; }
        done
    done
    return 1
}

probe() {
    local out=logs/sniff-probe.txt extcap ifs i
    {
        echo "### date";            date
        echo "### tshark";          echo "$tshark"; "$tshark" -v 2>&1 | head -1
        echo "### tshark -G folders"; "$tshark" -G folders 2>&1
        echo "### tshark -D";       "$tshark" -D 2>&1
        local d x
        for d in ~/.local/lib/wireshark/extcap /Applications/Wireshark.app/Contents/MacOS/extcap; do
            echo "### ls $d"; ls -la "$d" 2>&1
            for x in "$d"/*(N*); do
                echo "### $x --extcap-interfaces"; "$x" --extcap-interfaces 2>&1 | head -40
            done
        done
        echo "### nrfutil"; command -v nrfutil && nrfutil list 2>&1 | head -20
        echo "### nrfutil device list"; nrfutil device list 2>&1 | head -60
        echo "### nrfutil ble-sniffer --help"; nrfutil ble-sniffer --help 2>&1 | head -60
        echo "### nrfutil ble-sniffer sniff --help"; nrfutil ble-sniffer sniff --help 2>&1 | head -120
        echo "### shim --help"; ~/.local/lib/wireshark/extcap/nrfutil-ble-sniffer-shim --help 2>&1 | head -60
        echo "### shim config.json"; cat ~/.local/lib/wireshark/extcap/nrfutil-ble-sniffer-shim-config.json 2>&1
        echo "### ls /dev/cu.usbmodem*"; ls /dev/cu.usbmodem* 2>&1
        echo "### system_profiler SPUSBDataType (Nordic / Seeed)"
        system_profiler SPUSBDataType 2>/dev/null | grep -i -B2 -A8 -E 'nordic|nrf|seeed|xiao|sniffer' | head -80
        extcap=$(find_extcap)
        echo "### extcap";          echo "${extcap:-NOT FOUND}"
        if [[ -n "$extcap" ]]; then
            echo "### --extcap-interfaces"; "$extcap" --extcap-interfaces 2>&1
            ifs=("${(@f)$("$extcap" --extcap-interfaces 2>/dev/null |
                    sed -n 's/^interface {value=\([^}]*\)}.*/\1/p')}")
            for i in $ifs; do
                [[ -z "$i" ]] && continue
                echo "### --extcap-dlts  $i";  "$extcap" --extcap-dlts --extcap-interface "$i" 2>&1
                echo "### --extcap-config $i"; "$extcap" --extcap-config --extcap-interface "$i" 2>&1
            done
            echo "### extcap --help"; "$extcap" --help 2>&1 | head -80
        fi
    } > "$out" 2>&1
    echo "wrote $out"
}


# --- sniffer port: what the nRF Sniffer shim lists as an interface ----------
sniffer_port() {
    local shim=~/.local/lib/wireshark/extcap/nrfutil-ble-sniffer-shim
    [[ -x "$shim" ]] || return 1
    "$shim" --extcap-interfaces 2>/dev/null |
        sed -n 's/^interface {value=\([^}]*\)}.*/\1/p' | head -1
}

newest_console_log() {
    ls -t logs/console-*.log 2>/dev/null | head -1
}

flash_dongle() {
    # nrfutil ble-sniffer ships the firmware under <nrfutil home>/share/
    # nrfutil-ble-sniffer/firmware; fall back to an unzipped nRF Sniffer package.
    local fwdirs=(~/.nrfutil/share/nrfutil-ble-sniffer/firmware ~/Downloads) zip hex f
    echo ">>> firmware files:"
    ls -la ${fwdirs[1]} 2>/dev/null
    zip=$(find $fwdirs -iname '*sniffer*52840dongle*.zip' 2>/dev/null | sort | tail -1)
    hex=$(find $fwdirs -iname '*sniffer*52840dongle*.hex' 2>/dev/null | sort | tail -1)
    if [[ -z "$zip" && -z "$hex" ]]; then
        echo "no nRF52840 Dongle sniffer firmware found in: $fwdirs" >&2
        echo "Download the nRF Sniffer for Bluetooth LE package from Nordic, unzip it into ~/Downloads, and retry." >&2
        return 1
    fi
    if [[ -z "$zip" ]]; then
        echo ">>> firmware (hex): $hex -> building a DFU package"
        if ! nrfutil list 2>/dev/null | grep -q '^nrf5sdk-tools'; then
            echo ">>> installing nrfutil nrf5sdk-tools (for 'nrfutil pkg generate')"
            nrfutil install nrf5sdk-tools || return 1
        fi
        zip=logs/sniffer-dongle-dfu.zip
        nrfutil pkg generate --hw-version 52 --sd-req 0x00 --application-version 1 \
            --application "$hex" "$zip" || return 1
    fi
    echo ">>> firmware (DFU zip): $zip"
    echo ">>> press the dongle's RESET (side) button: the red LED pulses = bootloader."
    echo -n ">>> then press Enter... "; read -r
    nrfutil device program --firmware "$zip" --traits nordicDfu || return 1
    echo ">>> done. Re-plug the dongle, then: ./sniff.sh probe (it should now list an interface)."
}

capture() {
    local port=${SNIFF_PORT:-$(sniffer_port)} clog=$(newest_console_log)
    local addr=${KB_ADDR:-} ltk=${LTK:-} out pid start reason=${STOP_REASON:-0x24}
    if [[ -z "$port" ]]; then
        echo "no nRF Sniffer interface found (./sniff.sh probe; flash the dongle?)" >&2; return 1
    fi
    if [[ -z "$addr" && -n "$clog" ]]; then
        # newest log first, latest line in it first
        addr=$(ls -t logs/console-*.log | while read -r f; do
                   sed 's/\x1b\[[0-9;]*m//g' "$f" | grep 'ble_conn: host .* connected' |
                   sed -n 's/.* local \([0-9A-F:]*\) (\([a-z]*\)).*/\1 \2/p' | tail -1
               done | head -1)
    fi
    if [[ -z "$ltk" && -n "$clog" ]]; then
        ltk=$(ls -t logs/console-*.log | xargs cat | sed 's/\x1b\[[0-9;]*m//g' |
              sed -n 's/.*SC LTK: \(0x[0-9a-fA-F]*\).*/\1/p' | head -1)
    fi
    [[ -z "$addr" ]] && { echo "keyboard address unknown (set KB_ADDR='AA:..:FF random')" >&2; return 1; }
    [[ -z "$ltk"  ]] && { echo "SC LTK unknown (re-pair with CONFIG_BT_LOG_SNIFFER_INFO, or set LTK=0x...)" >&2; return 1; }
    out=logs/sniff-$(date +%Y%m%d-%H%M%S).pcap
    echo ">>> port $port, follow '$addr', SC LTK ${ltk[1,8]}..., -> $out"
    echo ">>> stops ${STOP_AFTER:-5}s after a host disconnect ($reason) in ${clog:-<no console log>}, or Ctrl-C"
    # Watcher (background): when the console logs a host disconnect with the
    # given reason, wait STOP_AFTER s and SIGINT the sniffer, found by its
    # unique output path. The sniffer itself runs in the foreground, so a
    # Ctrl-C in the terminal reaches it directly.
    start=$(wc -l < "${clog:-/dev/null}")
    (
        [[ -z "$clog" ]] && exit 0
        while sleep 1; do
            if tail -n +$((start + 1)) "$clog" | grep -q "ble_conn: host .* disconnected: $reason"; then
                echo ">>> host disconnect ($reason) seen at $(date +%T); stopping in ${STOP_AFTER:-5}s"
                sleep ${STOP_AFTER:-5}
                pkill -INT -f -- "--output-pcap-file $out"
                exit 0
            fi
        done
    ) &
    pid=$!
    nrfutil ble-sniffer sniff --port "$port" --follow "$addr" --sc-ltk-key "$ltk" \
        --output-pcap-file "$out" --log-level info > "${out%.pcap}.sniffer.log" 2>&1
    kill $pid 2>/dev/null
    echo ">>> saved $out ($(wc -c < "$out" 2>/dev/null || echo 0) bytes)"
}

case "${1:-}" in
    probe)        probe ;;
    flash-dongle) flash_dongle ;;
    capture)      capture ;;
    *) echo "usage: $0 probe | flash-dongle | capture" >&2; exit 1 ;;
esac
