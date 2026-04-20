#!/usr/bin/env bash
set -euo pipefail

# ========================================
#  Agent Pack — One-Click Installer
#  Linux Edition
# ========================================

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$INSTALLER_DIR/lib"

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
fi

# Source library functions
source "$LIB_DIR/install-hermes.sh"
source "$LIB_DIR/install-openclaw.sh"
source "$LIB_DIR/configure-llm.sh"

echo ""
echo "========================================"
echo "  Agent Pack Installer for Linux"
echo "========================================"
echo ""

# ---- Step 1: Product Selection ----
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

# ---- Step 2: Install Products ----
# Both Hermes and OpenClaw delegate to their official install.sh scripts,
# which handle all dependency detection and installation internally.
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) install_hermes ;;
        openclaw) install_openclaw ;;
    esac
done

# ---- Step 3: Configure LLM ----
configure_llm "${SELECTED_PRODUCTS[@]}"

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
