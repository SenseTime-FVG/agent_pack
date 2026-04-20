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
    # Under WSL, /mnt/<drive> paths are inherited from Windows PATH and every
    # file shows up as executable.  openclaw's install.sh uses `command -v
    # corepack` to detect a corepack binary; if the user has a Windows-side
    # corepack on PATH (e.g. /mnt/d/tools/corepack) it wins, and the Linux
    # kernel can't execute a PE binary, aborting the install with:
    #   cannot execute: required file not found
    # Strip /mnt/* entries from PATH for just this sub-shell to keep the
    # lookup Linux-only.  We only do this under WSL so native Linux installs
    # aren't affected.
    local child_path="$PATH"
    if grep -qi microsoft /proc/version 2>/dev/null; then
        child_path="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd:)"
    fi

    # When hermes installs first it sets npm's global prefix to
    # $HERMES_HOME/node (e.g. /root/.hermes/node).  openclaw then runs
    # `npm install -g pnpm@10` which lands in $prefix/bin — but that dir
    # isn't on PATH, so the subsequent `command -v pnpm` check fails and
    # openclaw aborts with "pnpm installation failed" even though the
    # install succeeded.  Prepend the current global prefix's bin/ to PATH
    # so the follow-up lookup finds pnpm regardless of where hermes put it.
    local npm_prefix=""
    if command -v npm >/dev/null 2>&1; then
        npm_prefix="$(PATH="$child_path" npm config get prefix 2>/dev/null || true)"
    fi
    if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ]; then
        child_path="$npm_prefix/bin:$child_path"
    fi

    PATH="$child_path" bash "$install_script" \
        --install-method git \
        --source-ready \
        --git-dir "$OPENCLAW_INSTALL_DIR" \
        --no-onboard --no-prompt
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: OpenClaw installation failed (exit code $rc)."
        return 1
    fi

    # Enable local gateway mode unconditionally so `openclaw gateway` works
    # out of the box — even when the user skipped LLM setup (empty API key).
    # Without this, launching the gateway fails with:
    #   Gateway start blocked: set gateway.mode=local (current: unset)
    # `openclaw config set` is idempotent; re-running the installer is safe.
    # Use $child_path for the lookup too, because openclaw was just installed
    # to $npm_prefix/bin which may not be on the outer shell's PATH yet.
    if PATH="$child_path" command -v openclaw >/dev/null 2>&1; then
        if ! PATH="$child_path" openclaw config set gateway.mode local >/dev/null 2>&1; then
            echo "[!] Could not set gateway.mode=local automatically."
            echo "    Run: openclaw config set gateway.mode local"
        fi
    else
        echo "[!] openclaw not found on PATH after install — skipping gateway.mode=local."
        echo "    Run: openclaw config set gateway.mode local"
    fi

    echo "[OK] OpenClaw installed."
}
