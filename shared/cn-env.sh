#!/usr/bin/env bash
# CN-region environment helpers, shared between linux/ and windows/ (via WSL).
# Source this file (don't execute) when AGENTPACK_CN=1 to:
#   1. Export package-manager env vars (uv / pip / npm / python-build-standalone)
#      pointing at domestic mirrors.
#   2. Pre-install uv via a ghproxy-wrapped install.sh so the vendored
#      hermes install.sh's direct `curl https://astral.sh/uv/install.sh | sh`
#      call is skipped (it short-circuits when `uv` is already on PATH).
#   3. Rewrite /etc/apt/sources.list (or ubuntu.sources on noble+) to the
#      TUNA mirror for supported Ubuntu codenames.  Other distros /
#      unsupported codenames print a warning and leave apt untouched.
#
# Env vars that callers may rely on after sourcing:
#   UV_INSTALLER_GITHUB_BASE_URL  UV_INDEX_URL  UV_DEFAULT_INDEX
#   PIP_INDEX_URL  UV_PYTHON_INSTALL_MIRROR  npm_config_registry
#
# Keep this aligned with windows/scripts/wsl-common.ps1's mirror constants.

_AP_CN_NPM_REGISTRY="https://registry.npmmirror.com"
_AP_CN_PIP_INDEX="https://mirrors.aliyun.com/pypi/simple/"
_AP_CN_UV_PYTHON_MIRROR="https://registry.npmmirror.com/-/binary/python-build-standalone"
# ghproxy.cn is the primary GitHub proxy used elsewhere in this repo; reuse it
# so uv fetches its release tarballs through the same mirror that agent_pack
# itself is cloned from.
_AP_CN_GHPROXY="https://ghproxy.cn/"

# TUNA-supported Ubuntu codenames.  Source:
#   https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu/
# Anything outside this set triggers a warning and the apt source is left
# alone.  Update this list when TUNA adds/removes versions.
_AP_CN_TUNA_UBUNTU_CODENAMES="bionic focal jammy noble oracular plucky"

apply_cn_package_mirrors() {
    export UV_INDEX_URL="$_AP_CN_PIP_INDEX"
    export UV_DEFAULT_INDEX="$_AP_CN_PIP_INDEX"
    export PIP_INDEX_URL="$_AP_CN_PIP_INDEX"
    export UV_PYTHON_INSTALL_MIRROR="$_AP_CN_UV_PYTHON_MIRROR"
    export npm_config_registry="$_AP_CN_NPM_REGISTRY"
    # Route uv's own release downloads through ghproxy so the binary install
    # works without hitting github.com directly.  Value is a base URL; uv
    # appends /astral-sh/uv/releases/download/<ver>/<artifact>.
    export UV_INSTALLER_GITHUB_BASE_URL="${_AP_CN_GHPROXY}https://github.com"
}

# Pre-install uv through the ghproxy-wrapped install.sh.  No-op if uv is
# already on PATH (or already installed to a known location).
preinstall_uv_cn() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$HOME/.local/bin/uv" ] || [ -x "$HOME/.cargo/bin/uv" ]; then
        return 0
    fi

    echo "[*] Pre-installing uv via CN mirror (ghproxy + UV_INSTALLER_GITHUB_BASE_URL)..."
    local script_url="${_AP_CN_GHPROXY}https://raw.githubusercontent.com/astral-sh/uv/main/scripts/install.sh"
    if curl -LsSf --max-time 30 "$script_url" | sh >/dev/null 2>&1; then
        echo "[OK] uv pre-installed via CN mirror."
        return 0
    fi

    # Fall back to astral.sh directly; the vendored install.sh will also try
    # this, so a failure here is non-fatal.
    echo "[!] CN-mirror uv install failed; upstream install.sh will retry via astral.sh."
    return 0
}

# Rewrite apt sources to TUNA for supported Ubuntu codenames.  Silent no-op
# for non-Ubuntu hosts; warning-only for Ubuntu codenames TUNA does not list.
apply_tuna_apt_mirror() {
    [ -r /etc/os-release ] || return 0
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        return 0
    fi

    local codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$codename" ]; then
        echo "[!] Could not determine Ubuntu codename; leaving apt sources unchanged." >&2
        return 0
    fi

    case " $_AP_CN_TUNA_UBUNTU_CODENAMES " in
        *" $codename "*) ;;
        *)
            echo "[!] Ubuntu '$codename' is not listed on https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu/ — leaving apt sources unchanged." >&2
            return 0
            ;;
    esac

    # Ubuntu 24.04+ ships the deb822-style /etc/apt/sources.list.d/ubuntu.sources
    # and leaves /etc/apt/sources.list empty.  Detect and rewrite the right one.
    local deb822="/etc/apt/sources.list.d/ubuntu.sources"
    local legacy="/etc/apt/sources.list"
    local sudo=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo="sudo"
        else
            echo "[!] Need root to rewrite apt sources but sudo is unavailable; skipping TUNA mirror." >&2
            return 0
        fi
    fi

    local tuna_base="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
    if [ -f "$deb822" ]; then
        echo "[*] Switching $deb822 to TUNA ($codename)..."
        $sudo cp -a "$deb822" "${deb822}.agent-pack.bak" 2>/dev/null || true
        $sudo sed -i -E \
            -e 's|https?://[^ ]*archive\.ubuntu\.com/ubuntu/?|'"$tuna_base"'|g' \
            -e 's|https?://[^ ]*security\.ubuntu\.com/ubuntu/?|'"$tuna_base"'|g' \
            -e 's|https?://[^ ]*ports\.ubuntu\.com/ubuntu-ports/?|'"$tuna_base"'-ports|g' \
            "$deb822"
        echo "[OK] apt sources updated (backup: ${deb822}.agent-pack.bak)"
    elif [ -s "$legacy" ]; then
        echo "[*] Switching $legacy to TUNA ($codename)..."
        $sudo cp -a "$legacy" "${legacy}.agent-pack.bak" 2>/dev/null || true
        $sudo sed -i -E \
            -e 's|https?://[^ ]*archive\.ubuntu\.com/ubuntu/?|'"$tuna_base"'|g' \
            -e 's|https?://[^ ]*security\.ubuntu\.com/ubuntu/?|'"$tuna_base"'|g' \
            -e 's|https?://[^ ]*ports\.ubuntu\.com/ubuntu-ports/?|'"$tuna_base"'-ports|g' \
            "$legacy"
        echo "[OK] apt sources updated (backup: ${legacy}.agent-pack.bak)"
    else
        echo "[!] No apt sources file found to rewrite; skipping TUNA mirror." >&2
        return 0
    fi
}

# Convenience: apply all CN tweaks in one call.  Safe to call multiple times.
apply_cn_env() {
    apply_cn_package_mirrors
    apply_tuna_apt_mirror
    preinstall_uv_cn
}
