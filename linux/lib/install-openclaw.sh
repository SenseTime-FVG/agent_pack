#!/usr/bin/env bash
# Install OpenClaw by cloning the agent_pack monorepo and delegating to
# repos/openclaw/scripts/install.sh with --install-method git --source-ready.
#
# agent_pack is now the source of truth for our vendored copy of OpenClaw, so
# we install in "git" mode (from our own source tree) rather than from the
# public npm registry.  The old `--install-method npm` path is no longer used.

_AP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_AP_DEFAULTS_JSON="$_AP_ROOT/config/defaults.json"
_AP_FETCH="$_AP_ROOT/shared/fetch-agent-pack.sh"

_openclaw_get() { python3 -c "import json; print(json.load(open('$_AP_DEFAULTS_JSON'))$1)" 2>/dev/null; }

OPENCLAW_INSTALL_DIR_DEFAULT="$(_openclaw_get "['openclaw']['install_dir']")"
OPENCLAW_INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-${OPENCLAW_INSTALL_DIR_DEFAULT//\$HOME/$HOME}}"

install_openclaw() {
    echo ""
    echo "========================================"
    echo "  Installing OpenClaw"
    echo "========================================"

    if [ ! -x "$_AP_FETCH" ]; then
        chmod +x "$_AP_FETCH" 2>/dev/null || true
    fi

    echo "[*] Fetching openclaw source from agent_pack..."
    if ! bash "$_AP_FETCH" "repos/openclaw" "$OPENCLAW_INSTALL_DIR"; then
        echo "[!] ERROR: Failed to fetch openclaw source."
        return 1
    fi

    local install_script="$OPENCLAW_INSTALL_DIR/scripts/install.sh"
    if [ ! -f "$install_script" ]; then
        echo "[!] ERROR: $install_script not found after fetch."
        return 1
    fi

    echo "[*] Running openclaw install.sh (git --source-ready)..."
    bash "$install_script" \
        --install-method git \
        --source-ready \
        --git-dir "$OPENCLAW_INSTALL_DIR" \
        --no-onboard --no-prompt
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: OpenClaw installation failed (exit code $rc)."
        return 1
    fi

    echo "[OK] OpenClaw installed."
}
