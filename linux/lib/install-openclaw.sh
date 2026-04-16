#!/usr/bin/env bash
# Install OpenClaw

OPENCLAW_CONFIG="$HOME/.openclaw"

install_openclaw() {
    echo ""
    echo "========================================"
    echo "  Installing OpenClaw"
    echo "========================================"

    echo "[*] Installing OpenClaw via npm..."
    npm install -g openclaw@latest

    mkdir -p "$OPENCLAW_CONFIG"

    if [ ! -f "$OPENCLAW_CONFIG/openclaw.json" ]; then
        cat > "$OPENCLAW_CONFIG/openclaw.json" << 'EOF'
{
  "agent": {
    "model": ""
  }
}
EOF
    fi

    echo "[OK] OpenClaw installed."
}
