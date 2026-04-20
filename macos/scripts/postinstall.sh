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

# Collect LLM configuration up front (mirrors the Windows installer wizard).
collect_llm_config

# Product selection
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
    *) SELECTED_PRODUCTS=("hermes") ;;
esac

# Clone agent_pack once here so install_hermes + install_openclaw copy from
# a shared cache instead of each cloning the repo independently.
AGENT_PACK_CLONE_ROOT="$(mktemp -d)/agent_pack"
echo "[*] Pre-fetching agent_pack (shared across product installs)..."
if ! bash "$SHARED_DIR/prefetch-agent-pack.sh" "$AGENT_PACK_CLONE_ROOT"; then
    echo "[!] Failed to pre-fetch agent_pack."
    exit 1
fi
export AGENT_PACK_CACHE_DIR="$AGENT_PACK_CLONE_ROOT"

# Install products and write each product's LLM config right after its
# install succeeds — so a later product's failure can't strand an already
# installed one without credentials.
for prod in "${SELECTED_PRODUCTS[@]}"; do
    case "$prod" in
        hermes) install_hermes ;;
        openclaw) install_openclaw ;;
    esac
    apply_llm_config_for "$prod"
done

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

# End-of-install: take over the current Terminal window with one agent, and
# if a second one was selected, open a second Terminal tab for it.  We do NOT
# spawn fresh windows — the goal is that the user keeps using the install
# window, now running the agent, instead of ending up with extra sessions.
#
# Choice of which runs where: Hermes (interactive REPL) lives in this
# window because that's the user's current focus; OpenClaw gateway
# (long-running server, mostly background) lives in the extra tab.
_open_terminal_tab() {
    local cmd="$1"
    local title="$2"
    # Run a login shell so PATH picks up brew + npm globals.  After the
    # product exits, drop to an interactive shell so the window/tab stays
    # open to read final output.
    local wrapped="$cmd; echo; echo '[agent-pack] $title exited.'; exec bash -l"
    local escaped="${wrapped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    osascript <<OSA >/dev/null 2>&1
tell application "Terminal"
    activate
    tell application "System Events" to keystroke "t" using {command down}
    delay 0.3
    do script "$escaped" in selected tab of the front window
end tell
OSA
}

_run_in_this_window_then_replace() {
    # exec hands the current bash process over to the product; when the
    # product exits, the window stays open because Terminal keeps a dead
    # shell visible until the user closes the tab themselves.
    local cmd="$1"
    local title="$2"
    echo "[*] Starting $title in this window..."
    exec bash -lc "$cmd"
}

# Decide which agent takes this window vs. the new tab.  When openclaw is
# present, schedule a delayed `openclaw dashboard` call so the control UI
# opens in the user's browser shortly after the gateway starts.
_has() { for p in "${SELECTED_PRODUCTS[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }

_schedule_dashboard() {
    # Run through a login shell so openclaw's install dir (e.g. ~/.local/bin
    # or the homebrew prefix) is on PATH — this script's own shell may have
    # been invoked from the installer with a stripped environment.
    ( sleep 3 && bash -lc 'openclaw dashboard >/dev/null 2>&1' ) &
    disown 2>/dev/null || true
}

if _has openclaw && _has hermes; then
    _open_terminal_tab 'openclaw gateway --verbose' 'OpenClaw Gateway'
    _schedule_dashboard
    echo "[*] Opening OpenClaw dashboard in your browser shortly..."
    _run_in_this_window_then_replace 'hermes' 'Hermes Agent'
elif _has hermes; then
    _run_in_this_window_then_replace 'hermes' 'Hermes Agent'
elif _has openclaw; then
    _schedule_dashboard
    echo "[*] Opening OpenClaw dashboard in your browser shortly..."
    _run_in_this_window_then_replace 'openclaw gateway --verbose' 'OpenClaw Gateway'
fi
SETUP_SCRIPT

chmod +x "$INSTALL_DIR/setup-interactive.sh"

# Launch Terminal with the interactive setup
open -a Terminal "$INSTALL_DIR/setup-interactive.sh"

exit 0
