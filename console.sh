#!/bin/zsh
# Monitor the XIAO's ZMK log console (3rd CDC port), auto-reconnecting when the
# board reboots (e.g. after flashing new firmware pulls the port out from under
# `cat`). Before each (re)connect, the 1st CDC port (the 1200bps bootloader
# watcher) is briefly opened with no read/write -- just to toggle DTR / resync
# the board's USB CDC state -- then closed.
#
# Ctrl-C always stops the script for good: SIGINT is trapped into a flag that
# is checked right after every `cat` returns, so a reconnect in progress can't
# swallow the interrupt.
#
# Usage: ./console.sh

should_exit=0
trap 'should_exit=1' INT TERM

# Find the XIAO's 3-port CDC cluster among all /dev/cu.usbmodem* ports, even
# when other USB-serial devices (e.g. an nRF52840 sniffer dongle) are also
# plugged in. The XIAO always exposes 3 ports from the SAME underlying
# composite device, whose numbers share a common prefix and end in ...01
# (bootloader/1200bps watcher), ...04, and ...06 (log console) -- an
# unrelated device's port numbers land in a different prefix entirely, so
# matching by "same prefix, suffix set {01,04,06}" reliably picks out just
# the XIAO even with a sniffer or other board also attached. Prints the
# watcher port then the log port, one per line, on stdout when found.
find_xiao_ports() {
    local -A by_prefix
    local p base suffix
    for p in /dev/cu.usbmodem*(N); do
        [[ "$p" =~ '^.*usbmodem([0-9]+)$' ]] || continue
        local num=$match[1]
        base=${num[1,-3]}
        suffix=${num[-2,-1]}
        by_prefix[$base]+="$suffix "
    done
    for base in ${(k)by_prefix}; do
        local suffixes=(${=by_prefix[$base]})
        if [[ " ${suffixes[*]} " == *' 01 '* && " ${suffixes[*]} " == *' 04 '* \
              && " ${suffixes[*]} " == *' 06 '* ]]; then
            print -- "/dev/cu.usbmodem${base}01"
            print -- "/dev/cu.usbmodem${base}06"
            return 0
        fi
    done
    return 1
}

# Block (checking should_exit) until the XIAO's port cluster is found.
wait_for_ports() {
    while (( ! should_exit )); do
        find_xiao_ports && return 0
        sleep 0.3
    done
    return 1
}

echo ">>> console: waiting for board... (Ctrl-C to quit)"

while (( ! should_exit )); do
    ports=("${(@f)$(wait_for_ports)}")
    (( should_exit || ${#ports[@]} < 2 )) && break

    first_cu=${ports[1]}
    log_cu=${ports[2]}
    first_tty=${first_cu/cu./tty.}

    # Pin the watcher port to a safe baud BEFORE opening it, so the open+close
    # below can't be mistaken for the Arduino-style 1200bps touch (which would
    # reboot the board into the UF2 bootloader).
    stty -f "$first_cu" 115200 raw -echo 2>/dev/null || true

    echo ">>> toggling $first_tty (open+close, no I/O)"
    python3 -c '
import os, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY)
os.close(fd)
' "$first_tty" 2>/dev/null || true

    sleep 0.3
    (( should_exit )) && break

    echo ">>> monitoring $log_cu (115200, Ctrl-C to stop)"
    stty -f "$log_cu" 115200 raw -echo 2>/dev/null || true
    cat "$log_cu" 2>/dev/null
    # cat returns either because the port disappeared (board rebooted -- I/O
    # error/EOF) or because we were interrupted (Ctrl-C, which also set
    # should_exit via the trap). Either way, loop back around: should_exit
    # breaks out for good, otherwise we wait for the port to come back.

    (( should_exit )) && break
    echo ">>> port lost -- waiting for the board to come back..."
    sleep 0.5
done

echo ">>> console: stopped"
