#!/usr/bin/env bash
# postinstall.sh — Main installation logic after pkg payload is deployed.
# Payload is installed to /usr/local/lib/agent-pack/ by pkgbuild.

set -euo pipefail

INSTALL_DIR="/usr/local/lib/agent-pack"
GUI_SETUP="$INSTALL_DIR/macos/gui-setup.sh"

CONSOLE_USER="$(stat -f '%Su' /dev/console)"
POSTINSTALL_LOG="/private/tmp/agent-pack-postinstall.log"
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
    USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
    if [ -n "${USER_HOME:-}" ] && [ -d "$USER_HOME" ]; then
        POSTINSTALL_LOG_DIR="$USER_HOME/Library/Logs/AgentPack"
        mkdir -p "$POSTINSTALL_LOG_DIR"
        chown "$CONSOLE_USER" "$POSTINSTALL_LOG_DIR" 2>/dev/null || true
        POSTINSTALL_LOG="$POSTINSTALL_LOG_DIR/postinstall.log"
    fi
fi

mkdir -p "$(dirname "$POSTINSTALL_LOG")"
exec >>"$POSTINSTALL_LOG" 2>&1
echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Agent Pack macOS postinstall"
echo "[*] Writing postinstall log to: $POSTINSTALL_LOG"

if [ ! -f "$GUI_SETUP" ]; then
    echo "[!] GUI setup script not found: $GUI_SETUP"
    exit 1
fi

chmod 755 "$GUI_SETUP"

if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
    echo "[!] Could not determine a logged-in user for GUI setup."
    exit 1
fi

CONSOLE_UID="$(id -u "$CONSOLE_USER")"
GUI_CONFIG="/private/tmp/agent-pack-installer-${CONSOLE_UID}.json"
echo "[*] Launching GUI setup as $CONSOLE_USER (uid $CONSOLE_UID)"

if ! /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /bin/bash -lc \
    "AGENTPACK_GUI_CONFIG='$GUI_CONFIG' /usr/bin/nohup '$GUI_SETUP' >/dev/null 2>&1 &"; then
    echo "[!] Failed to launch GUI setup."
    exit 1
fi

echo "[OK] GUI setup launched."
exit 0
