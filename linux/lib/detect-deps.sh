#!/usr/bin/env bash
# Detect and install system dependencies.
# Sources this file — functions available to caller.

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_LIKE="$ID_LIKE"
    elif command -v lsb_release &>/dev/null; then
        DISTRO_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        DISTRO_LIKE=""
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi
    export DISTRO_ID DISTRO_LIKE
}

pkg_install() {
    local packages=("$@")
    case "$DISTRO_ID" in
        ubuntu|debian|pop|linuxmint)
            sudo apt-get update -qq
            sudo apt-get install -y -qq "${packages[@]}"
            ;;
        fedora|rhel|centos|rocky|alma)
            sudo dnf install -y -q "${packages[@]}"
            ;;
        arch|manjaro|endeavouros)
            sudo pacman -Sy --noconfirm --needed "${packages[@]}"
            ;;
        *)
            if echo "$DISTRO_LIKE" | grep -q debian; then
                sudo apt-get update -qq
                sudo apt-get install -y -qq "${packages[@]}"
            elif echo "$DISTRO_LIKE" | grep -q fedora; then
                sudo dnf install -y -q "${packages[@]}"
            else
                echo "ERROR: Unsupported distro '$DISTRO_ID'."
                echo "Please install manually: ${packages[*]}"
                return 1
            fi
            ;;
    esac
}

ensure_git() {
    if ! command -v git &>/dev/null; then
        echo "[*] Installing git..."
        pkg_install git
    fi
    echo "[OK] git $(git --version | cut -d' ' -f3)"
}

ensure_python() {
    if command -v python3.11 &>/dev/null; then
        PYTHON_CMD="python3.11"
    elif command -v python3 &>/dev/null; then
        local ver
        ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        if [ "$ver" = "3.11" ]; then
            PYTHON_CMD="python3"
        fi
    fi

    if [ -z "${PYTHON_CMD:-}" ]; then
        echo "[*] Installing Python 3.11..."
        case "$DISTRO_ID" in
            ubuntu|debian|pop|linuxmint)
                sudo apt-get update -qq
                sudo apt-get install -y -qq software-properties-common
                sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
                sudo apt-get update -qq
                sudo apt-get install -y -qq python3.11 python3.11-venv python3.11-dev
                ;;
            fedora|rhel|centos|rocky|alma)
                sudo dnf install -y -q python3.11 python3.11-devel
                ;;
            arch|manjaro|endeavouros)
                sudo pacman -Sy --noconfirm --needed python
                ;;
            *)
                pkg_install python3.11 || pkg_install python3
                ;;
        esac
        PYTHON_CMD="python3.11"
        if ! command -v python3.11 &>/dev/null; then
            PYTHON_CMD="python3"
        fi
    fi
    export PYTHON_CMD
    echo "[OK] Python: $($PYTHON_CMD --version)"
}

ensure_node() {
    local need_install=false
    if command -v node &>/dev/null; then
        local major
        major=$(node -v | sed 's/v//' | cut -d. -f1)
        if [ "$major" -lt 22 ]; then
            need_install=true
        fi
    else
        need_install=true
    fi

    if [ "$need_install" = true ]; then
        echo "[*] Installing Node.js 22..."
        if command -v curl &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>/dev/null
            sudo apt-get install -y -qq nodejs 2>/dev/null || \
            sudo dnf install -y -q nodejs 2>/dev/null || \
            sudo pacman -Sy --noconfirm nodejs npm 2>/dev/null
        else
            pkg_install nodejs npm
        fi
    fi
    echo "[OK] Node.js: $(node -v)"
}

ensure_uv() {
    if ! command -v uv &>/dev/null; then
        echo "[*] Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    echo "[OK] uv: $(uv --version)"
}

ensure_build_tools() {
    echo "[*] Ensuring build tools..."
    case "$DISTRO_ID" in
        ubuntu|debian|pop|linuxmint)
            pkg_install build-essential libffi-dev
            ;;
        fedora|rhel|centos|rocky|alma)
            pkg_install gcc gcc-c++ libffi-devel
            ;;
        arch|manjaro|endeavouros)
            pkg_install base-devel libffi
            ;;
    esac
}
