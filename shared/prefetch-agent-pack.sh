#!/usr/bin/env bash
# Clone agent_pack once into a target directory, for use as a cache shared
# across multiple fetch-agent-pack.sh invocations in the same install session.
#
# Used by macOS postinstall and Windows prefetch-agent-pack.ps1 (Linux reuses
# install.sh's own bootstrap clone).  Honors CN mirrors from defaults.json the
# same way fetch-agent-pack.sh does.
#
# Usage:
#   prefetch-agent-pack.sh <target_dir>
#
# After success, the caller should:
#   export AGENT_PACK_CACHE_DIR="<target_dir>"
# so subsequent fetch-agent-pack.sh calls copy from the cache instead of
# cloning again.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: prefetch-agent-pack.sh <target_dir>" >&2
    exit 2
fi

TARGET="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_JSON="$SCRIPT_DIR/../config/defaults.json"
if [ ! -f "$DEFAULTS_JSON" ]; then
    echo "[!] defaults.json not found at $DEFAULTS_JSON" >&2
    exit 1
fi

_json_get() {
    python3 -c "import json,sys; data=json.load(open('$DEFAULTS_JSON')); print($1)" 2>/dev/null || true
}

REPO_URL="$(_json_get "data['agent_pack']['repo_url']")"
BRANCH="$(_json_get "data['agent_pack']['branch']")"
MIRRORS_RAW="$(_json_get "'\n'.join(data['agent_pack'].get('cn_mirrors', []))")"

if [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
    echo "[!] Could not read agent_pack.repo_url / branch from defaults.json" >&2
    exit 1
fi

_detect_cn() {
    case "${AGENTPACK_CN:-}" in
        1|true|TRUE|yes|YES) return 0 ;;
        0|false|FALSE|no|NO) return 1 ;;
    esac
    local country
    country="$(curl -fsSL --max-time 5 https://api.iping.cc/v1/query 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('country_code',''))" 2>/dev/null || true)"
    [ "$country" = "CN" ]
}

_build_url_list() {
    echo "$REPO_URL"
    if _detect_cn; then
        while IFS= read -r mirror; do
            [ -n "$mirror" ] || continue
            echo "${mirror%/}/$REPO_URL"
        done <<<"$MIRRORS_RAW"
    fi
}

if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
fi
mkdir -p "$(dirname "$TARGET")"

CLONE_OK=0
while IFS= read -r url; do
    [ -n "$url" ] || continue
    echo "[*] Trying clone: $url"
    if git clone --depth 1 --branch "$BRANCH" "$url" "$TARGET" 2>&1; then
        CLONE_OK=1
        break
    fi
    rm -rf "$TARGET"
    echo "[!] Clone failed via $url — trying next source"
done < <(_build_url_list)

if [ $CLONE_OK -ne 1 ]; then
    echo "[!] Failed to clone agent_pack from any source." >&2
    exit 1
fi

echo "[OK] agent_pack cached at $TARGET"
