#!/usr/bin/env bash
# Install Hermes Agent by cloning the agent_pack monorepo and delegating to
# repos/hermes-agent/scripts/install.sh with --source-ready.
#
# Since agent_pack is now the source of truth for our vendored copy of
# hermes-agent, we do NOT fall back to the upstream NousResearch repo.
# Bundled/offline install is no longer supported — all platforms clone.

_AP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_AP_DEFAULTS_JSON="$_AP_ROOT/config/defaults.json"
_AP_FETCH="$_AP_ROOT/shared/fetch-agent-pack.sh"

_hermes_get() { python3 -c "import json; print(json.load(open('$_AP_DEFAULTS_JSON'))$1)" 2>/dev/null; }

HERMES_BRANCH="${HERMES_BRANCH:-$(_hermes_get "['hermes']['branch']")}"
HERMES_INSTALL_DIR_DEFAULT="$(_hermes_get "['hermes']['install_dir']")"
# defaults.json stores "$HOME/..." as a literal string; expand it here.
HERMES_INSTALL_DIR="${HERMES_INSTALL_DIR:-${HERMES_INSTALL_DIR_DEFAULT//\$HOME/$HOME}}"

install_hermes() {
    echo ""
    echo "========================================"
    echo "  Installing Hermes Agent"
    echo "========================================"

    if [ ! -x "$_AP_FETCH" ]; then
        chmod +x "$_AP_FETCH" 2>/dev/null || true
    fi

    echo "[*] Fetching hermes-agent source from agent_pack..."
    if ! bash "$_AP_FETCH" "repos/hermes-agent" "$HERMES_INSTALL_DIR"; then
        echo "[!] ERROR: Failed to fetch hermes-agent source."
        return 1
    fi

    local install_script="$HERMES_INSTALL_DIR/scripts/install.sh"
    if [ ! -f "$install_script" ]; then
        echo "[!] ERROR: $install_script not found after fetch."
        return 1
    fi

    echo "[*] Running hermes install.sh (--source-ready)..."
    bash "$install_script" --source-ready --skip-setup \
        --dir "$HERMES_INSTALL_DIR" --branch "$HERMES_BRANCH"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: Hermes Agent installation failed (exit code $rc)."
        return 1
    fi

    echo "[OK] Hermes Agent installed."
}
