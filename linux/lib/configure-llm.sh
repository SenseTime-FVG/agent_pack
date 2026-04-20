#!/usr/bin/env bash
# Interactive LLM provider configuration.
# Provider details (base_url, default_model, signup_url) are read from
# config/defaults.json so there is a single source of truth.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../../shared" && pwd)"
_DEFAULTS_JSON="$(cd "$SCRIPT_DIR/../.." && pwd)/config/defaults.json"

# Helper: read a value from defaults.json
_cfg() { python3 -c "import json; print(json.load(open('$_DEFAULTS_JSON'))$1)" 2>/dev/null; }

configure_llm() {
    local products=("$@")

    echo ""
    echo "========================================"
    echo "  LLM Provider Configuration"
    echo "========================================"
    echo ""
    echo "Select your LLM provider:"
    echo "  1) $(_cfg "['llm_providers']['openrouter']['name']")"
    echo "  2) $(_cfg "['llm_providers']['openai']['name']")"
    echo "  3) $(_cfg "['llm_providers']['anthropic']['name']")"
    echo "  4) $(_cfg "['llm_providers']['custom']['name']")"
    echo ""

    local choice
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"

    local provider base_url model
    case "$choice" in
        1) provider="openrouter"
           base_url="$(_cfg "['llm_providers']['openrouter']['base_url']")"
           model="$(_cfg "['llm_providers']['openrouter']['default_model']")"
           ;;
        2) provider="openai"
           base_url="$(_cfg "['llm_providers']['openai']['base_url']")"
           model="$(_cfg "['llm_providers']['openai']['default_model']")"
           ;;
        3) provider="anthropic"
           base_url="$(_cfg "['llm_providers']['anthropic']['base_url']")"
           model="$(_cfg "['llm_providers']['anthropic']['default_model']")"
           ;;
        4) provider="custom"
           read -rp "Base URL: " base_url
           read -rp "Model name: " model
           ;;
        *) echo "Invalid choice, defaulting to OpenRouter."
           provider="openrouter"
           base_url="$(_cfg "['llm_providers']['openrouter']['base_url']")"
           model="$(_cfg "['llm_providers']['openrouter']['default_model']")"
           ;;
    esac

    local signup_url
    signup_url="$(_cfg "['llm_providers']['$provider']['signup_url']")"
    if [ -n "$signup_url" ]; then
        echo ""
        echo "Get your key at: $signup_url"
    fi

    echo ""
    read -rsp "API Key: " api_key
    echo ""

    if [ -z "$api_key" ]; then
        echo "WARNING: No API key provided. You can configure it later."
        return 0
    fi

    # Verify connection if python3 is available
    local python_cmd="${PYTHON_CMD:-python3}"
    if command -v "$python_cmd" &>/dev/null && [ -f "$SHARED_DIR/verify-llm.py" ]; then
        echo "[*] Verifying API connection..."
        if "$python_cmd" "$SHARED_DIR/verify-llm.py" \
            --provider "$provider" \
            --api-key "$api_key" \
            --base-url "$base_url" \
            --model "$model"; then
            echo "[OK] Connection verified!"
        else
            echo "WARNING: Could not verify connection. Saving config anyway."
        fi
    fi

    for prod in "${products[@]}"; do
        case "$prod" in
            hermes)
                mkdir -p "$HOME/.hermes"
                cat > "$HOME/.hermes/config.yaml" << YAML
provider: $provider
model: $model
api_key: $api_key
base_url: $base_url
YAML
                echo "[OK] Hermes config written to ~/.hermes/config.yaml"
                ;;
            openclaw)
                mkdir -p "$HOME/.openclaw"
                local provider_prefix
                case "$provider" in
                    openrouter) provider_prefix="openrouter" ;;
                    openai) provider_prefix="openai" ;;
                    anthropic) provider_prefix="anthropic" ;;
                    *) provider_prefix="openai" ;;
                esac
                cat > "$HOME/.openclaw/openclaw.json" << JSON
{
  "agent": {
    "model": "${provider_prefix}/${model}"
  },
  "providers": {
    "${provider_prefix}": {
      "apiKey": "${api_key}"
    }
  }
}
JSON
                echo "[OK] OpenClaw config written to ~/.openclaw/openclaw.json"
                ;;
        esac
    done
}
