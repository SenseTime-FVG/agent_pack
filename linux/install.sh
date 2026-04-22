#!/usr/bin/env bash
set -euo pipefail

# ========================================
#  Agent Pack — One-Click Installer
#  Linux Edition
# ========================================

# When invoked as `curl ... | bash`, bash's stdin is the pipe carrying the
# script body, so every `read -rp` inside hits EOF and silently accepts
# defaults — the user sees no prompts and ends up with Hermes installed and
# no LLM config written.  Rebind stdin to the controlling tty so prompts
# work in that flow.  No-op when stdin is already a tty (plain `bash
# install.sh`) or when there's no tty to fall back to (CI, containers).
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec </dev/tty
fi

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$INSTALLER_DIR/lib"
AGENT_PACK_CLONE_ROOT=""

# If running via curl | bash, download the full package first.
# This bootstrap can't read config/defaults.json yet (we haven't fetched it),
# so the repo URL + CN mirrors are duplicated here as a minimal bootstrap.
# Keep the mirror list in sync with config/defaults.json (agent_pack.cn_mirrors).
AGENT_PACK_REPO="https://github.com/SenseTime-FVG/agent_pack.git"
if [ ! -d "$LIB_DIR" ]; then
    echo "[*] Downloading Agent Pack installer..."
    TMPDIR=$(mktemp -d)
    _cloned=0
    _bootstrap_try() {
        git clone -q --depth 1 "$1" "$TMPDIR/agent-pack" 2>/dev/null
    }
    if _bootstrap_try "$AGENT_PACK_REPO"; then
        _cloned=1
    else
        for _mirror in "https://ghproxy.cn/" "https://ghfast.top/"; do
            rm -rf "$TMPDIR/agent-pack"
            if _bootstrap_try "${_mirror}${AGENT_PACK_REPO}"; then
                _cloned=1
                break
            fi
        done
    fi
    if [ "$_cloned" -ne 1 ]; then
        echo "[!] Failed to clone $AGENT_PACK_REPO (direct and via CN mirrors)." >&2
        exit 1
    fi
    INSTALLER_DIR="$TMPDIR/agent-pack/linux"
    LIB_DIR="$INSTALLER_DIR/lib"
    # Bootstrap clone doubles as the shared cache: fetch-agent-pack.sh will
    # copy repos/<agent> straight from here instead of cloning again.
    AGENT_PACK_CLONE_ROOT="$TMPDIR/agent-pack"
fi

# Source library functions
source "$LIB_DIR/install-hermes.sh"
source "$LIB_DIR/install-openclaw.sh"
source "$LIB_DIR/configure-llm.sh"

# CN-region environment setup: mirror env vars + TUNA apt + pre-installed uv.
# Driven by AGENTPACK_CN=1 or a CN network probe inside cn-env.sh's caller.
_AP_SHARED_DIR="$(cd "$INSTALLER_DIR/../shared" && pwd)"
if [ -f "$_AP_SHARED_DIR/cn-env.sh" ]; then
    # shellcheck disable=SC1091
    source "$_AP_SHARED_DIR/cn-env.sh"
    _ap_cn_detected=0
    case "${AGENTPACK_CN:-}" in
        1|true|TRUE|yes|YES) _ap_cn_detected=1 ;;
        0|false|FALSE|no|NO) _ap_cn_detected=0 ;;
        *)
            country="$(curl -fsSL --max-time 5 https://api.iping.cc/v1/query 2>/dev/null \
                | python3 -c "import json,sys; print(json.load(sys.stdin).get('country_code',''))" 2>/dev/null || true)"
            [ "$country" = "CN" ] && _ap_cn_detected=1
            ;;
    esac
    if [ "$_ap_cn_detected" -eq 1 ]; then
        export AGENTPACK_CN=1
        echo "[OK] Detected China network — using domestic mirrors (TUNA apt / npm / pip / uv)"
        apply_cn_env
    fi
fi

# If the bootstrap didn't already provide a clone (i.e. user ran install.sh
# from a local checkout), fetch once now so both install_hermes and
# install_openclaw can share the same source tree.  Runs after CN detection
# so prefetch itself honors mirrors.
if [ -z "$AGENT_PACK_CLONE_ROOT" ]; then
    AGENT_PACK_CLONE_ROOT="$(mktemp -d)/agent_pack"
    echo "[*] Pre-fetching agent_pack (shared across product installs)..."
    if ! bash "$_AP_SHARED_DIR/prefetch-agent-pack.sh" "$AGENT_PACK_CLONE_ROOT"; then
        echo "[!] Failed to pre-fetch agent_pack." >&2
        exit 1
    fi
fi
export AGENT_PACK_CACHE_DIR="$AGENT_PACK_CLONE_ROOT"

echo ""
echo "========================================"
echo "  Agent Pack Installer for Linux"
echo "========================================"
echo ""

# ---- Step 1: Collect LLM Configuration ----
# Ask up front (mirrors the Windows installer wizard) so the user is done
# with interactive prompts before the long-running installs start.
collect_llm_config

# ---- Step 2: Product Selection ----
echo ""
echo "Which products would you like to install?"
echo "  1) Hermes Agent"
echo "  2) OpenClaw"
echo "  3) Both"
echo ""
read -rp "Choice [1]: " product_choice
product_choice="${product_choice:-1}"

SELECTED_PRODUCTS=()
case "$product_choice" in
    1) SELECTED_PRODUCTS=("hermes") ;;
    2) SELECTED_PRODUCTS=("openclaw") ;;
    3) SELECTED_PRODUCTS=("hermes" "openclaw") ;;
    *) echo "Invalid choice. Defaulting to Hermes Agent."; SELECTED_PRODUCTS=("hermes") ;;
esac

echo ""
echo "Selected: ${SELECTED_PRODUCTS[*]}"
echo ""

# ---- Step 3: Install Products + Write Per-Product LLM Config ----
# Both Hermes and OpenClaw delegate to their official install.sh scripts,
# which handle all dependency detection and installation internally.
# As soon as a product installs successfully we write its LLM config so a
# later product's failure doesn't strand the working one without credentials.
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) install_hermes ;;
        openclaw) install_openclaw ;;
    esac
    apply_llm_config_for "$prod"
done

# ---- Done ----
echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) echo "  Hermes Agent:  Run 'hermes' to start chatting" ;;
        openclaw) echo "  OpenClaw:      Run 'openclaw gateway' to start the gateway" ;;
    esac
done
echo ""
echo "  You may need to restart your shell or run: source ~/.bashrc"
echo ""

# ---- Step 4: Launch Installed Products In This Window ----
# Take over this install session with the selected agent(s).  When both are
# selected, background `openclaw gateway` (logs to ~/.openclaw/gateway.log)
# and exec hermes in the foreground — a gateway is a server, a hermes REPL
# needs stdin.  When only one is selected, exec it directly.
#
# When openclaw is among the selected products, also trigger
# `openclaw dashboard` a few seconds later to open the control UI in the
# user's browser.  It reads the same config the gateway just started with,
# so URL + token match.
#
# PATH augmentation: hermes installs to $HERMES_HOME/node/bin and openclaw's
# CLI wrapper lands in ~/.local/bin.  Neither is guaranteed to be on the
# current shell's PATH at this point — it usually only picks them up after
# the user re-sources ~/.bashrc.  Add them explicitly so the exec below
# works without a shell restart.
_ap_has() { for p in "${SELECTED_PRODUCTS[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }

_ap_augment_path() {
    local add
    for add in "$HOME/.local/bin" "$HOME/.hermes/node/bin" "$HERMES_INSTALL_DIR/node/bin"; do
        [ -z "$add" ] && continue
        case ":$PATH:" in *":$add:"*) ;; *) [ -d "$add" ] && PATH="$add:$PATH" ;; esac
    done
    export PATH
}

_ap_schedule_dashboard() {
    # Give the gateway a few seconds to bind before opening the browser
    # (dashboard itself doesn't probe, so we sleep for the user's sake).
    ( sleep 3 && openclaw dashboard >/dev/null 2>&1 ) &
    disown 2>/dev/null || true
}

_ap_augment_path

if _ap_has openclaw && _ap_has hermes; then
    _openclaw_log="$HOME/.openclaw/gateway.log"
    mkdir -p "$(dirname "$_openclaw_log")"
    echo "[*] Starting openclaw gateway in the background (log: $_openclaw_log)..."
    nohup openclaw gateway --verbose >"$_openclaw_log" 2>&1 &
    disown 2>/dev/null || true
    _ap_schedule_dashboard
    echo "[*] Opening OpenClaw dashboard in your browser shortly..."
    echo "[*] Starting hermes in this window..."
    exec hermes
elif _ap_has hermes; then
    echo "[*] Starting hermes in this window..."
    exec hermes
elif _ap_has openclaw; then
    _ap_schedule_dashboard
    echo "[*] Opening OpenClaw dashboard in your browser shortly..."
    echo "[*] Starting openclaw gateway in this window..."
    exec openclaw gateway --verbose
fi
