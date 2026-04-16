#!/usr/bin/env bash
# preinstall.sh — Run before payload is installed.
# Ensures Homebrew and Xcode CLI tools are available.

set -e

echo "[Agent Pack] Pre-install: checking prerequisites..."

# Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "[*] Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please complete the Xcode CLT installation and re-run this installer."
    exit 1
fi

# Homebrew
if ! command -v brew &>/dev/null; then
    echo "[*] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to path for Apple Silicon
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

echo "[OK] Prerequisites ready."
exit 0
