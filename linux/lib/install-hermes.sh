#!/usr/bin/env bash
# Install Hermes Agent — delegates to the official installer script.
#
# The official script (scripts/install.sh inside hermes-agent) handles all
# dependency detection, venv creation, pip install, PATH setup, and config
# templating.  We call it with --skip-setup so that Agent Pack's own LLM
# configuration step runs instead of the interactive setup wizard.
#
# Environment variables consumed:
#   HERMES_LOCAL_SOURCE  — path to a pre-cloned hermes-agent repo (bundled install)

HERMES_LOCAL_SOURCE="${HERMES_LOCAL_SOURCE:-}"

# Read config from defaults.json
_DEFAULTS_JSON="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/defaults.json"
_hermes_get() { python3 -c "import json; print(json.load(open('$_DEFAULTS_JSON'))$1)" 2>/dev/null; }
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-$(_hermes_get "['hermes']['install_script_url']")}"
HERMES_BRANCH="${HERMES_BRANCH:-$(_hermes_get "['hermes']['branch']")}"

install_hermes() {
    echo ""
    echo "========================================"
    echo "  Installing Hermes Agent"
    echo "========================================"

    if [ -n "$HERMES_LOCAL_SOURCE" ] && [ -d "$HERMES_LOCAL_SOURCE" ]; then
        # ── Bundled source (Windows installer / offline) ──
        local target_dir="$HOME/.hermes/hermes-agent"
        if [ -d "$target_dir" ]; then
            rm -rf "$target_dir"
        fi
        mkdir -p "$(dirname "$target_dir")"
        cp -a "$HERMES_LOCAL_SOURCE" "$target_dir"

        local install_script="$target_dir/scripts/install.sh"
        if [ ! -f "$install_script" ]; then
            echo "[!] ERROR: Bundled source does not contain scripts/install.sh"
            echo "    Expected at: $install_script"
            return 1
        fi

        echo "[*] Installing from bundled source..."
        bash "$install_script" --skip-setup --dir "$target_dir" --branch "$HERMES_BRANCH"
    else
        # ── Online install — download and run the official script ──
        echo "[*] Running official Hermes Agent installer..."
        curl -fsSL "$HERMES_INSTALL_URL" \
            | bash -s -- --skip-setup --branch "$HERMES_BRANCH"
    fi

    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: Hermes Agent installation failed (exit code $rc)."
        return 1
    fi

    echo "[OK] Hermes Agent installed."
}
