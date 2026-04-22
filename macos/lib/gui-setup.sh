#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/usr/local/lib/agent-pack"
WIZARD_SWIFT="$INSTALL_DIR/macos/gui-wizard.swift"
PRODUCT_SESSION_SCRIPT="$INSTALL_DIR/macos/product-session.sh"
LOG_DIR="$HOME/Library/Logs/AgentPack"
LOG_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/install-$LOG_TIMESTAMP.log"
LATEST_LOG_LINK="$LOG_DIR/install.latest.log"
LEGACY_LOG_LINK="$LOG_DIR/install.log"
PRECOLLECTED_CONFIG="${AGENTPACK_GUI_CONFIG:-}"

mkdir -p "$LOG_DIR"
: >"$LOG_FILE"
ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LOG_LINK"
ln -sfn "$(basename "$LOG_FILE")" "$LEGACY_LOG_LINK"
exec >>"$LOG_FILE" 2>&1

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Agent Pack macOS GUI setup"
echo "[*] Writing install log to: $LOG_FILE"
echo "[*] Latest install log link: $LATEST_LOG_LINK"

setup_brew_env() {
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    fi
}

cd "${HOME:-/tmp}" 2>/dev/null || cd /tmp
setup_brew_env

collect_gui_inputs() {
    local tmp_json rc clang_cache swift_cache

    if [ -n "$PRECOLLECTED_CONFIG" ] && [ -f "$PRECOLLECTED_CONFIG" ]; then
        tmp_json="$PRECOLLECTED_CONFIG"
    else
        if [ ! -f "$WIZARD_SWIFT" ]; then
            echo "[!] GUI wizard not found: $WIZARD_SWIFT"
            return 1
        fi

        tmp_json="$(mktemp "${TMPDIR:-/tmp}/agent-pack-gui.XXXXXX.json")"
        clang_cache="/tmp/agent-pack-clang-cache-$(id -u)"
        swift_cache="/tmp/agent-pack-swift-cache-$(id -u)"
        if env CLANG_MODULE_CACHE_PATH="$clang_cache" SWIFT_MODULE_CACHE_PATH="$swift_cache" \
            /usr/bin/swift "$WIZARD_SWIFT" >"$tmp_json"; then
            :
        else
            rc=$?
            rm -f "$tmp_json"
            if [ "$rc" -eq 128 ]; then
                echo "[*] User canceled Agent Pack GUI setup."
                exit 0
            fi
            echo "[!] GUI wizard failed with exit code $rc."
            return "$rc"
        fi
    fi

    eval "$(
        python3 - "$tmp_json" <<'PY'
import json
import shlex
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
products = " ".join(shlex.quote(item) for item in data["products"])

print(f"SELECTED_PRODUCTS=({products})")
print(f"LLM_PROVIDER={shlex.quote(data['provider'])}")
print(f"LLM_BASE_URL={shlex.quote(data['base_url'])}")
print(f"LLM_MODEL={shlex.quote(data['model'])}")
print(f"LLM_API_KEY={shlex.quote(data['api_key'])}")
PY
    )"
    rm -f "$tmp_json"

    export LLM_PROVIDER LLM_BASE_URL LLM_MODEL LLM_API_KEY
    echo "[*] Selected products: ${SELECTED_PRODUCTS[*]}"
    echo "[*] Selected provider: $LLM_PROVIDER"
    echo "[*] Selected model: $LLM_MODEL"
}

has_product() {
    local target="$1"
    local prod

    for prod in "${SELECTED_PRODUCTS[@]}"; do
        if [ "$prod" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

open_log_file() {
    /usr/bin/open -a TextEdit "$LOG_FILE" >/dev/null 2>&1 \
        || /usr/bin/open -R "$LOG_FILE" >/dev/null 2>&1 \
        || /usr/bin/open "$LOG_DIR" >/dev/null 2>&1 \
        || true
}

open_terminal_window_command() {
    local cmd="$1"
    local title="$2"
    local wrapped="$cmd; echo; echo '[agent-pack] $title exited.'; exec bash -l"
    local escaped="${wrapped//\\/\\\\}"

    escaped="${escaped//\"/\\\"}"
    if ! /usr/bin/osascript <<OSA
tell application "Terminal"
    activate
    do script "$escaped"
end tell
OSA
    then
        echo "[!] Failed to open Terminal window for $title."
        return 1
    fi
}

launch_product_terminal() {
    local product="$1"
    local title="$2"
    local session_cmd=""

    if [ ! -f "$PRODUCT_SESSION_SCRIPT" ]; then
        echo "[!] Product session script not found: $PRODUCT_SESSION_SCRIPT"
        return 1
    fi

    printf -v session_cmd \
        'env AGENTPACK_PRODUCT=%q AGENTPACK_LLM_PROVIDER=%q AGENTPACK_LLM_BASE_URL=%q AGENTPACK_LLM_MODEL=%q AGENTPACK_LLM_API_KEY=%q /bin/bash %q' \
        "$product" "$LLM_PROVIDER" "$LLM_BASE_URL" "$LLM_MODEL" "$LLM_API_KEY" "$PRODUCT_SESSION_SCRIPT"
    open_terminal_window_command "$session_cmd" "$title"
    echo "[OK] Launched $title Terminal session."
}

main() {
    collect_gui_inputs || return 1

    if has_product hermes; then
        if ! launch_product_terminal hermes "Hermes Agent"; then
            return 1
        fi
    fi

    if has_product openclaw; then
        if has_product hermes; then
            sleep 0.5
        fi
        if ! launch_product_terminal openclaw "OpenClaw"; then
            return 1
        fi
    fi

    echo "[OK] Agent Pack macOS GUI setup dispatched all selected product sessions."
}

if ! main; then
    echo "[!] Agent Pack macOS GUI setup failed. Opening the install log."
    open_log_file
    exit 1
fi
