#!/usr/bin/env bash
# preinstall.sh — Run before payload is installed.
# Checks platform-level prerequisites and guides the user to install them.

set -e

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

echo "[OK] Prerequisites ready."
exit 0
