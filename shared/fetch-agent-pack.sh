#!/usr/bin/env bash
# Fetch agent_pack and copy one subdirectory into place.
#
# Used by linux/lib/install-*.sh and by windows/scripts/install-*.ps1
# (invoked inside WSL).  Honors CN mirrors from config/defaults.json when
# China region is detected (AGENTPACK_CN=1 forces it; AGENTPACK_CN=0 skips).
#
# Usage:
#   fetch-agent-pack.sh <subdir> <target_dir>
#
# Example:
#   fetch-agent-pack.sh repos/hermes-agent "$HOME/.agent-pack/repos/hermes-agent"
#
# Behavior:
#   - Wipes $target_dir if it already exists.
#   - If $AGENT_PACK_CACHE_DIR is set and contains <subdir>, copies directly
#     from the cache — no clone.  Orchestrators (linux install.sh, macOS
#     setup-interactive.sh, windows prefetch-agent-pack.ps1) set this once so
#     installing Hermes + OpenClaw in the same session shares one clone.
#   - Otherwise: tries direct clone first; on failure, retries through each
#     CN mirror listed in defaults.json.
#   - Removes the embedded .git after copying so install.sh treats the tree as
#     source-only (no accidental git pull).

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: fetch-agent-pack.sh <subdir> <target_dir>" >&2
    exit 2
fi

SUBDIR="$1"
TARGET="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_JSON="$SCRIPT_DIR/../config/defaults.json"
if [ ! -f "$DEFAULTS_JSON" ]; then
    echo "[!] defaults.json not found at $DEFAULTS_JSON" >&2
    exit 1
fi

_json_get() {
    # _json_get <python-expression-on-data>
    python3 -c "import json,sys; data=json.load(open('$DEFAULTS_JSON')); print($1)" 2>/dev/null || true
}

REPO_URL="$(_json_get "data['agent_pack']['repo_url']")"
BRANCH="$(_json_get "data['agent_pack']['branch']")"
MIRRORS_RAW="$(_json_get "'\n'.join(data['agent_pack'].get('cn_mirrors', []))")"

if [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
    echo "[!] Could not read agent_pack.repo_url / branch from defaults.json" >&2
    exit 1
fi

_copy_from_source() {
    # _copy_from_source <src_subdir_root> — copy $1/$SUBDIR into $TARGET.
    local src_root="$1"
    local src="$src_root/$SUBDIR"
    if [ ! -d "$src" ]; then
        echo "[!] Subdirectory '$SUBDIR' not found in $src_root" >&2
        return 1
    fi
    if [ -d "$TARGET" ]; then
        rm -rf "$TARGET"
    fi
    mkdir -p "$(dirname "$TARGET")"
    cp -a "$src" "$TARGET"
    # Vendored copies don't carry .git, but belt-and-suspenders: make sure the
    # downstream install.sh can't accidentally treat the copy as a git repo.
    rm -rf "$TARGET/.git"
    echo "[OK] agent_pack/$SUBDIR copied to $TARGET"
}

# Fast path: orchestrator already cloned agent_pack once (linux install.sh
# bootstrap, macOS setup-interactive.sh, windows prefetch-agent-pack.ps1) and
# pointed us at it via $AGENT_PACK_CACHE_DIR.  Skip the clone entirely.
if [ -n "${AGENT_PACK_CACHE_DIR:-}" ] && [ -d "${AGENT_PACK_CACHE_DIR}/$SUBDIR" ]; then
    echo "[*] Using cached agent_pack at $AGENT_PACK_CACHE_DIR"
    _copy_from_source "$AGENT_PACK_CACHE_DIR"
    exit $?
fi

_detect_cn() {
    # Explicit override wins.
    case "${AGENTPACK_CN:-}" in
        1|true|TRUE|yes|YES) return 0 ;;
        0|false|FALSE|no|NO) return 1 ;;
    esac
    # Network probe (short timeout; best effort).
    local country
    country="$(curl -fsSL --max-time 5 https://api.iping.cc/v1/query 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('country_code',''))" 2>/dev/null || true)"
    [ "$country" = "CN" ]
}

_build_url_list() {
    # Direct URL first; then each mirror-prefixed URL if CN.
    echo "$REPO_URL"
    if _detect_cn; then
        while IFS= read -r mirror; do
            [ -n "$mirror" ] || continue
            echo "${mirror%/}/$REPO_URL"
        done <<<"$MIRRORS_RAW"
    fi
}

_try_clone() {
    local url="$1"
    local dest="$2"
    echo "[*] Trying clone: $url"
    if git clone --depth 1 --branch "$BRANCH" "$url" "$dest" 2>&1; then
        return 0
    fi
    rm -rf "$dest"
    return 1
}

TMPDIR_CLONE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CLONE"' EXIT

CLONE_OK=0
while IFS= read -r url; do
    [ -n "$url" ] || continue
    if _try_clone "$url" "$TMPDIR_CLONE/agent_pack"; then
        CLONE_OK=1
        break
    fi
    echo "[!] Clone failed via $url — trying next source"
done < <(_build_url_list)

if [ $CLONE_OK -ne 1 ]; then
    echo "[!] Failed to clone agent_pack from any source." >&2
    exit 1
fi

_copy_from_source "$TMPDIR_CLONE/agent_pack"
