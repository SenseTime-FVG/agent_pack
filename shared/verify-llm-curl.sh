#!/usr/bin/env bash

set -euo pipefail

provider=""
api_key=""
base_url=""
model=""

usage() {
    cat <<'EOF' >&2
Usage:
  verify-llm-curl.sh --provider <openrouter|openai|anthropic|custom> --api-key <key> [--base-url URL] [--model MODEL]
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --provider)
            provider="${2:-}"
            shift 2
            ;;
        --api-key)
            api_key="${2:-}"
            shift 2
            ;;
        --base-url)
            base_url="${2:-}"
            shift 2
            ;;
        --model)
            model="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -z "$provider" ] || [ -z "$api_key" ]; then
    echo "ERROR: --provider and --api-key are required" >&2
    usage
    exit 1
fi

case "$provider" in
    openrouter)
        : "${base_url:=https://openrouter.ai/api/v1}"
        : "${model:=nousresearch/hermes-3-llama-3.1-8b}"
        ;;
    openai)
        : "${base_url:=https://api.openai.com/v1}"
        : "${model:=gpt-4o-mini}"
        ;;
    anthropic)
        : "${base_url:=https://api.anthropic.com}"
        : "${model:=claude-sonnet-4-20250514}"
        ;;
    custom)
        ;;
    *)
        echo "ERROR: Unsupported provider: $provider" >&2
        exit 1
        ;;
esac

if [ -z "$base_url" ]; then
    echo "ERROR: --base-url required for custom provider" >&2
    exit 1
fi

if [ -z "$model" ]; then
    echo "ERROR: --model required for custom provider" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is not available on PATH" >&2
    exit 1
fi

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

run_curl_request() {
    local url="$1"
    local payload="$2"
    shift 2

    local body_file stderr_file http_code response_body stderr_text
    body_file="$(mktemp "${TMPDIR:-/tmp}/agent-pack-verify-body.XXXXXX")"
    stderr_file="$(mktemp "${TMPDIR:-/tmp}/agent-pack-verify-stderr.XXXXXX")"

    if http_code="$(curl -sS \
        --connect-timeout 15 \
        --max-time 45 \
        -o "$body_file" \
        -w '%{http_code}' \
        "$@" \
        --data "$payload" \
        "$url" 2>"$stderr_file")"; then
        :
    else
        stderr_text="$(cat "$stderr_file" 2>/dev/null || true)"
        rm -f "$body_file" "$stderr_file"
        echo "ERROR: ${stderr_text:-curl failed with no error output}" >&2
        return 1
    fi

    response_body="$(cat "$body_file" 2>/dev/null || true)"
    rm -f "$body_file" "$stderr_file"

    if [[ ! "$http_code" =~ ^2 ]]; then
        echo "ERROR: HTTP $http_code" >&2
        if [ -n "$response_body" ]; then
            echo "$response_body" >&2
        fi
        return 1
    fi

    printf '%s' "$response_body"
}

echo "Verifying $provider API at $base_url with model $model..."

if [ "$provider" = "anthropic" ]; then
    payload="$(printf '{"model":"%s","max_tokens":5,"messages":[{"role":"user","content":"Say OK"}]}' \
        "$(json_escape "$model")")"
    response_body="$(run_curl_request \
        "${base_url%/}/v1/messages" \
        "$payload" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01")" || {
        echo "FAIL: Could not verify LLM API connection." >&2
        exit 1
    }
    if printf '%s' "$response_body" | grep -q '"content"'; then
        echo "OK: LLM API connection verified successfully."
        exit 0
    fi
else
    payload="$(printf '{"model":"%s","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' \
        "$(json_escape "$model")")"
    response_body="$(run_curl_request \
        "${base_url%/}/chat/completions" \
        "$payload" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key")" || {
        echo "FAIL: Could not verify LLM API connection." >&2
        exit 1
    }
    if printf '%s' "$response_body" | grep -q '"choices"'; then
        echo "OK: LLM API connection verified successfully."
        exit 0
    fi
fi

echo "ERROR: Verification response did not include the expected fields." >&2
echo "FAIL: Could not verify LLM API connection." >&2
exit 1
