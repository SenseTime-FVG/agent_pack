#!/usr/bin/env bash
# Install skills from manifest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../../shared" && pwd)"

install_skills() {
    local products=("$@")

    echo ""
    echo "========================================"
    echo "  Installing Skills"
    echo "========================================"

    for prod in "${products[@]}"; do
        echo "[*] Fetching skills for $prod..."
        $PYTHON_CMD "$SHARED_DIR/fetch-skills.py" --product "$prod" || true
    done
}
