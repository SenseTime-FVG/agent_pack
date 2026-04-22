#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/usr/local/lib/agent-pack"
SHARED_DIR="$INSTALL_DIR/shared"
LINUX_LIB="$INSTALL_DIR/linux/lib"

PRODUCT="${AGENTPACK_PRODUCT:-}"
LLM_PROVIDER="${AGENTPACK_LLM_PROVIDER:-}"
LLM_BASE_URL="${AGENTPACK_LLM_BASE_URL:-}"
LLM_MODEL="${AGENTPACK_LLM_MODEL:-}"
LLM_API_KEY="${AGENTPACK_LLM_API_KEY:-}"

case "$PRODUCT" in
    hermes)
        PRODUCT_TITLE="Hermes Agent"
        ;;
    openclaw)
        PRODUCT_TITLE="OpenClaw"
        ;;
    *)
        echo "[!] Unsupported or missing AGENTPACK_PRODUCT: ${PRODUCT:-<empty>}" >&2
        exit 2
        ;;
esac

LOG_DIR="$HOME/Library/Logs/AgentPack"
LOG_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="$LOG_DIR/${PRODUCT}-session-$LOG_TIMESTAMP.log"
LATEST_LOG_LINK="$LOG_DIR/${PRODUCT}.latest.log"

mkdir -p "$LOG_DIR"
: >"$LOG_FILE"
ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LOG_LINK"
exec 3>&1 4>&2
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "[!] $PRODUCT_TITLE session failed."; echo "[*] Session log: $LOG_FILE"; fi' EXIT

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting $PRODUCT_TITLE session"
echo "[*] Writing session log to: $LOG_FILE"
echo "[*] Latest session log link: $LATEST_LOG_LINK"

setup_brew_env() {
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    fi
}

apply_cn_if_needed() {
    local country ap_cn_detected

    if [ ! -f "$SHARED_DIR/cn-env.sh" ]; then
        return 0
    fi

    # shellcheck disable=SC1091
    source "$SHARED_DIR/cn-env.sh"
    ap_cn_detected=0
    case "${AGENTPACK_CN:-}" in
        1|true|TRUE|yes|YES) ap_cn_detected=1 ;;
        0|false|FALSE|no|NO) ap_cn_detected=0 ;;
        *)
            country="$(curl -fsSL --max-time 5 https://api.iping.cc/v1/query 2>/dev/null \
                | python3 -c "import json,sys; print(json.load(sys.stdin).get('country_code',''))" 2>/dev/null || true)"
            [ "$country" = "CN" ] && ap_cn_detected=1
            ;;
    esac

    if [ "$ap_cn_detected" -eq 1 ]; then
        export AGENTPACK_CN=1
        echo "[OK] Detected China network — using domestic mirrors (npm / pip / uv)"
        apply_cn_env
    fi
}

resolve_cli() {
    local name="$1"
    local resolved=""

    hash -r 2>/dev/null || true
    resolved="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$resolved" ] && [ -x "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    case "$name" in
        hermes)
            for resolved in "$HOME/.local/bin/hermes" "/usr/local/bin/hermes" "/opt/homebrew/bin/hermes"; do
                if [ -x "$resolved" ]; then
                    printf '%s\n' "$resolved"
                    return 0
                fi
            done
            ;;
        openclaw)
            for resolved in "$HOME/.local/bin/openclaw" "/usr/local/bin/openclaw" "/opt/homebrew/bin/openclaw"; do
                if [ -x "$resolved" ]; then
                    printf '%s\n' "$resolved"
                    return 0
                fi
            done
            ;;
    esac

    return 1
}

schedule_openclaw_dashboard() {
    local openclaw_cli="$1"
    disown 2>/dev/null || true
    ( sleep 3 && "$openclaw_cli" dashboard >/dev/null 2>&1 ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

handoff_to_interactive_command() {
    exec 1>&3 2>&4
    exec 3>&- 4>&-
    exec "$@"
}

cd "${HOME:-/tmp}" 2>/dev/null || cd /tmp
setup_brew_env

source "$LINUX_LIB/install-hermes.sh"
source "$LINUX_LIB/install-openclaw.sh"
source "$LINUX_LIB/configure-llm.sh"

DISTRO_ID="macos"
export DISTRO_ID
export LLM_PROVIDER LLM_BASE_URL LLM_MODEL LLM_API_KEY

pkg_install() {
    brew install "$@"
}

echo "[*] Selected provider: $LLM_PROVIDER"
echo "[*] Selected model: $LLM_MODEL"
if [ -n "$LLM_BASE_URL" ]; then
    echo "[*] Selected base URL: $LLM_BASE_URL"
fi

apply_cn_if_needed

case "$PRODUCT" in
    hermes)
        install_hermes
        apply_llm_config_for hermes
        HERMES_CLI="$(resolve_cli hermes)" || {
            echo "[!] Hermes CLI not found after install."
            exit 1
        }
        echo "[OK] Launching Hermes in this Terminal..."
        handoff_to_interactive_command "$HERMES_CLI"
        ;;
    openclaw)
        install_openclaw
        apply_llm_config_for openclaw
        OPENCLAW_CLI="$(resolve_cli openclaw)" || {
            echo "[!] OpenClaw CLI not found after install."
            exit 1
        }
        echo "[*] Opening OpenClaw dashboard shortly..."
        schedule_openclaw_dashboard "$OPENCLAW_CLI"
        echo "[OK] Launching OpenClaw gateway in this Terminal..."
        handoff_to_interactive_command "$OPENCLAW_CLI" gateway --verbose
        ;;
esac
