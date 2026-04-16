#!/usr/bin/env bash
# Install Hermes Agent

HERMES_DIR="$HOME/.hermes-agent"
HERMES_CONFIG="$HOME/.hermes"

install_hermes() {
    echo ""
    echo "========================================"
    echo "  Installing Hermes Agent"
    echo "========================================"

    if [ -d "$HERMES_DIR" ]; then
        echo "[*] Updating existing Hermes Agent..."
        cd "$HERMES_DIR"
        git stash -q 2>/dev/null || true
        git pull -q origin main
    else
        echo "[*] Cloning Hermes Agent..."
        git clone -q https://github.com/NousResearch/hermes-agent.git "$HERMES_DIR"
        cd "$HERMES_DIR"
    fi

    echo "[*] Creating virtual environment..."
    uv venv venv --python 3.11 2>/dev/null || $PYTHON_CMD -m venv venv
    source venv/bin/activate

    echo "[*] Installing Python dependencies (this may take a few minutes)..."
    uv pip install -e ".[all]" 2>/dev/null || pip install -e ".[all]"

    deactivate

    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/hermes" << 'WRAPPER'
#!/usr/bin/env bash
source "$HOME/.hermes-agent/venv/bin/activate"
exec python -m hermes "$@"
WRAPPER
    chmod +x "$HOME/.local/bin/hermes"

    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            if [ -f "$rc" ]; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
            fi
        done
        export PATH="$HOME/.local/bin:$PATH"
    fi

    mkdir -p "$HERMES_CONFIG"

    echo "[OK] Hermes Agent installed."
}
