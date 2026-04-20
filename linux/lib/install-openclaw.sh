#!/usr/bin/env bash
# Install OpenClaw — delegates to the official installer script.
#
# The official script (scripts/install.sh inside openclaw) handles all
# dependency detection (Node.js, git, npm, Homebrew on macOS), installation,
# PATH setup, and config templating.
#
# We call it with --no-onboard so that Agent Pack's own LLM configuration
# step runs instead of the interactive onboarding wizard.
#
# Environment variables consumed:
#   OPENCLAW_LOCAL_SOURCE  — path to a pre-cloned openclaw repo (bundled install)

OPENCLAW_LOCAL_SOURCE="${OPENCLAW_LOCAL_SOURCE:-}"

# Read config from defaults.json
_DEFAULTS_JSON="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/defaults.json"
_openclaw_get() { python3 -c "import json; print(json.load(open('$_DEFAULTS_JSON'))$1)" 2>/dev/null; }
OPENCLAW_INSTALL_URL="${OPENCLAW_INSTALL_URL:-$(_openclaw_get "['openclaw']['install_script_url']")}"

install_openclaw() {
    echo ""
    echo "========================================"
    echo "  Installing OpenClaw"
    echo "========================================"

    if [ -n "$OPENCLAW_LOCAL_SOURCE" ] && [ -d "$OPENCLAW_LOCAL_SOURCE" ]; then
        # ── Bundled source (Windows installer / offline) ──
        local install_script="$OPENCLAW_LOCAL_SOURCE/scripts/install.sh"
        if [ ! -f "$install_script" ]; then
            echo "[!] ERROR: Bundled source does not contain scripts/install.sh"
            echo "    Expected at: $install_script"
            return 1
        fi

        # Use npm install method (not git): the bundled source may not
        # include .git metadata (Inno Setup and .pkg archives routinely drop
        # hidden directories), and git mode requires a valid work tree.
        # npm mode installs from the registry and works regardless.
        echo "[*] Installing from bundled source (npm method)..."
        bash "$install_script" --install-method npm --no-onboard --no-prompt
    else
        # ── Online install — download and run the official script ──
        echo "[*] Running official OpenClaw installer..."
        curl -fsSL --proto '=https' --tlsv1.2 "$OPENCLAW_INSTALL_URL" \
            | bash -s -- --no-onboard --no-prompt
    fi

    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: OpenClaw installation failed (exit code $rc)."
        return 1
    fi

    echo "[OK] OpenClaw installed."
}
