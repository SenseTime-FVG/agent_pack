#!/usr/bin/env bash
set -euo pipefail

# ========================================
#  Agent Pack — One-Click Installer
#  Linux Edition
# ========================================

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$INSTALLER_DIR/lib"

# If running via curl | bash, download the full package first
if [ ! -d "$LIB_DIR" ]; then
    echo "[*] Downloading Agent Pack installer..."
    TMPDIR=$(mktemp -d)
    git clone -q --depth 1 https://github.com/YOUR_ORG/agent-pack.git "$TMPDIR/agent-pack"
    INSTALLER_DIR="$TMPDIR/agent-pack/linux"
    LIB_DIR="$INSTALLER_DIR/lib"
fi

# Source library functions
source "$LIB_DIR/detect-deps.sh"
source "$LIB_DIR/install-hermes.sh"
source "$LIB_DIR/install-openclaw.sh"
source "$LIB_DIR/configure-llm.sh"
source "$LIB_DIR/install-skills.sh"

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

# ---- Step 2: Detect & Install Dependencies ----
echo "========================================"
echo "  Checking Dependencies"
echo "========================================"

detect_distro
echo "[*] Detected distro: $DISTRO_ID"

ensure_git

NEED_PYTHON=false
NEED_NODE=false
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) NEED_PYTHON=true ;;
        openclaw) NEED_NODE=true ;;
    esac
done

if [ "$NEED_PYTHON" = true ]; then
    ensure_python
    ensure_uv
    ensure_build_tools
fi

if [ "$NEED_NODE" = true ]; then
    ensure_node
fi

# ---- Step 3: Install Products ----
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) install_hermes ;;
        openclaw) install_openclaw ;;
    esac
done

# ---- Step 4: Configure LLM ----
configure_llm "${SELECTED_PRODUCTS[@]}"

# ---- Step 5: Install Skills ----
install_skills "${SELECTED_PRODUCTS[@]}"

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
