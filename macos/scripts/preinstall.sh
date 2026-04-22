#!/usr/bin/env bash
# preinstall.sh — Run before payload is installed.
# Checks platform-level prerequisites and collects GUI inputs up front.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUI_WIZARD="$SCRIPT_DIR/gui-wizard.swift"
DEFAULTS_JSON="$SCRIPT_DIR/defaults.json"
VERIFY_CURL_SCRIPT="$SCRIPT_DIR/verify-llm-curl.sh"

echo "[Agent Pack] Pre-install: checking prerequisites..."

# Installer runs with a stripped PATH on many macOS systems, so expose common
# Homebrew locations before checking for brew.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
fi

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo ""
    echo "============================================================"
    echo "  Xcode Command Line Tools are required but not installed."
    echo "============================================================"
    echo ""
    echo "  Please install them using one of the following methods:"
    echo ""
    echo "  Option 1 — Run in Terminal:"
    echo "    xcode-select --install"
    echo ""
    echo "  Option 2 — Download from Apple Developer:"
    echo "    https://developer.apple.com/download/all/"
    echo ""
    echo "  After installation completes, re-run the Agent Pack installer."
    echo ""
    exit 1
fi

# Homebrew
if ! command -v brew &>/dev/null; then
    echo ""
    echo "============================================================"
    echo "  Homebrew is required but not installed."
    echo "============================================================"
    echo ""
    echo "  Please install Homebrew first:"
    echo ""
    echo "    https://brew.sh"
    echo ""
    echo "  Quick install — paste this in Terminal:"
    echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo ""
    echo "  After installation completes, re-run the Agent Pack installer."
    echo ""
    exit 1
fi

if [ ! -f "$GUI_WIZARD" ] || [ ! -f "$DEFAULTS_JSON" ] || [ ! -f "$VERIFY_CURL_SCRIPT" ]; then
    echo "[!] GUI wizard assets missing in package scripts directory."
    exit 1
fi

CONSOLE_USER="$(stat -f '%Su' /dev/console)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
    echo "[!] Could not determine a logged-in user for GUI setup."
    exit 1
fi

CONSOLE_UID="$(id -u "$CONSOLE_USER")"
GUI_CONFIG="/private/tmp/agent-pack-installer-${CONSOLE_UID}.json"
GUI_CONFIG_TMP="${GUI_CONFIG}.tmp"
CLANG_CACHE="/tmp/agent-pack-clang-cache-${CONSOLE_UID}"
SWIFT_CACHE="/tmp/agent-pack-swift-cache-${CONSOLE_UID}"
rm -f "$GUI_CONFIG" "$GUI_CONFIG_TMP"

echo "[*] Collecting install choices and LLM config up front..."
if /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/env \
    AGENTPACK_DEFAULTS_JSON="$DEFAULTS_JSON" \
    AGENTPACK_VERIFY_CURL_SCRIPT="$VERIFY_CURL_SCRIPT" \
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    SWIFT_MODULE_CACHE_PATH="$SWIFT_CACHE" \
    /usr/bin/swift "$GUI_WIZARD" >"$GUI_CONFIG_TMP"; then
    :
else
    rc=$?
    rm -f "$GUI_CONFIG_TMP"
    if [ "$rc" -eq 128 ]; then
        echo "[*] User canceled Agent Pack setup."
    else
        echo "[!] GUI wizard failed with exit code $rc."
    fi
    exit 1
fi

mv "$GUI_CONFIG_TMP" "$GUI_CONFIG"
chown "$CONSOLE_USER" "$GUI_CONFIG" 2>/dev/null || true
chmod 600 "$GUI_CONFIG" 2>/dev/null || true

echo "[OK] Prerequisites ready and GUI config collected."
exit 0
