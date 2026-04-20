#!/usr/bin/env bash
# postinstall.sh — Main installation logic after pkg payload is deployed.
# Payload is installed to /usr/local/lib/agent-pack/ by pkgbuild.

set -e

INSTALL_DIR="/usr/local/lib/agent-pack"
SHARED_DIR="$INSTALL_DIR/shared"
CONFIG_DIR="$INSTALL_DIR/config"
LINUX_LIB="$INSTALL_DIR/linux/lib"

# Ensure brew is in PATH (Apple Silicon)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# The macOS .pkg can't do interactive UI during install,
# so we launch a Terminal window with the interactive setup script.

# Create the interactive setup script
cat > "$INSTALL_DIR/setup-interactive.sh" << 'SETUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/lib/agent-pack"
SHARED_DIR="$INSTALL_DIR/shared"
LINUX_LIB="$INSTALL_DIR/linux/lib"

# Reuse Linux library functions (they work on macOS bash too)
source "$LINUX_LIB/install-hermes.sh"
source "$LINUX_LIB/install-openclaw.sh"
source "$LINUX_LIB/configure-llm.sh"

# Ensure brew is in PATH (Apple Silicon)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo ""
echo "========================================"
echo "  Agent Pack Setup"
echo "========================================"
echo ""

# Override distro detection for macOS
DISTRO_ID="macos"
export DISTRO_ID

# Override package install for macOS
pkg_install() {
    brew install "$@"
}

# Product selection
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
    *) SELECTED_PRODUCTS=("hermes") ;;
esac

# Install products
# Both Hermes and OpenClaw delegate to their official install.sh scripts,
# which handle all dependency detection and installation internally.
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) install_hermes ;;
        openclaw) install_openclaw ;;
    esac
done

# Configure LLM
configure_llm "${SELECTED_PRODUCTS[@]}"

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
echo "Press Enter to close this window."
read -r
SETUP_SCRIPT

chmod +x "$INSTALL_DIR/setup-interactive.sh"

# Launch Terminal with the interactive setup
open -a Terminal "$INSTALL_DIR/setup-interactive.sh"

exit 0
