#!/usr/bin/env bash
# Launch installed products in their own terminal windows at the end of
# install.  Shared by:
#   - linux/install.sh                — native Linux path
#   - macos/scripts/postinstall.sh    — inlines this via $LINUX_LIB
#   - windows/installer.iss           — Windows spawns cmd windows directly,
#                                       does NOT call this file (kept here
#                                       only for single-source documentation
#                                       of the end-of-install UX)
#
# Hermes is an interactive REPL; `openclaw gateway` is a long-running server.
# Both deserve their own window so the user can see each one's output and
# Ctrl-C independently.
#
# Platform terminal-opener is pluggable: callers (e.g. macOS) can define
# `_ap_open_terminal` before sourcing this file to override the default
# Linux detection.

# Open a single terminal window running `cmd` with $title as its title.
# Returns 0 if it managed to spawn something, 1 if no terminal was available.
_ap_open_terminal_linux() {
    local title="$1"; shift
    local cmd="$*"

    # Need a display to open a GUI terminal.  SSH/headless paths fall through.
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        return 1
    fi

    # We wrap `cmd` with `exec bash -lc '<cmd>; exec bash'` so that after the
    # product exits (e.g. user Ctrl-C's the gateway) the shell stays open and
    # the user can read the final output before closing the window manually.
    local wrapped="$cmd; echo; echo '[agent-pack] $title exited. Press Ctrl-D to close.'; exec bash"

    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="$title" -- bash -lc "$wrapped" >/dev/null 2>&1 &
        return 0
    fi
    if command -v konsole >/dev/null 2>&1; then
        konsole --new-tab -p "tabtitle=$title" -e bash -lc "$wrapped" >/dev/null 2>&1 &
        return 0
    fi
    if command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal --title="$title" -e "bash -lc \"$wrapped\"" >/dev/null 2>&1 &
        return 0
    fi
    if command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -T "$title" -e bash -lc "$wrapped" >/dev/null 2>&1 &
        return 0
    fi
    if command -v xterm >/dev/null 2>&1; then
        xterm -T "$title" -e bash -lc "$wrapped" >/dev/null 2>&1 &
        return 0
    fi
    return 1
}

# Default opener = Linux.  macOS overrides this before sourcing to use
# Terminal.app via osascript.
if ! declare -F _ap_open_terminal >/dev/null 2>&1; then
    _ap_open_terminal() { _ap_open_terminal_linux "$@"; }
fi

# Headless fallback for openclaw: background it with nohup, log to a file,
# and tell the user how to tail the log and how to start hermes themselves
# (hermes is interactive so we can't daemonize it usefully).
_ap_launch_headless() {
    local products=("$@")
    local prod

    for prod in "${products[@]}"; do
        case "$prod" in
            openclaw)
                local log="$HOME/.openclaw/gateway.log"
                mkdir -p "$(dirname "$log")"
                echo "[*] No GUI terminal detected — starting 'openclaw gateway' in the background."
                echo "    Log: $log"
                nohup openclaw gateway --verbose >"$log" 2>&1 &
                disown 2>/dev/null || true
                ;;
            hermes)
                echo "[*] Hermes is interactive and cannot be launched headlessly."
                echo "    Start it in this shell with:  hermes"
                ;;
        esac
    done
}

# Public entry point.  Pass the list of installed product names.
launch_products() {
    local products=("$@")
    [ "${#products[@]}" -eq 0 ] && return 0

    echo ""
    echo "[*] Opening a terminal window for each product..."

    local any_gui=0
    local prod
    for prod in "${products[@]}"; do
        case "$prod" in
            hermes)
                if _ap_open_terminal "Hermes Agent" "hermes"; then
                    any_gui=1
                    echo "[OK] Launched Hermes Agent in a new terminal."
                fi
                ;;
            openclaw)
                if _ap_open_terminal "OpenClaw Gateway" "openclaw gateway --verbose"; then
                    any_gui=1
                    echo "[OK] Launched OpenClaw gateway in a new terminal."
                fi
                ;;
        esac
    done

    if [ "$any_gui" -eq 0 ]; then
        _ap_launch_headless "${products[@]}"
    fi
}
