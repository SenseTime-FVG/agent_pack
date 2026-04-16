#!/usr/bin/env bash
# Interactive LLM provider configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../../shared" && pwd)"

configure_llm() {
    local products=("$@")

    echo ""
    echo "========================================"
    echo "  LLM Provider Configuration"
    echo "========================================"
    echo ""
    echo "Select your LLM provider:"
    echo "  1) OpenRouter (recommended — 200+ models, free tier)"
    echo "  2) OpenAI"
    echo "  3) Anthropic"
    echo "  4) Custom endpoint"
    echo ""

    local choice
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"

    local provider base_url model
    case "$choice" in
        1) provider="openrouter"; base_url="https://openrouter.ai/api/v1"; model="nousresearch/hermes-3-llama-3.1-8b" ;;
        2) provider="openai"; base_url="https://api.openai.com/v1"; model="gpt-4o-mini" ;;
        3) provider="anthropic"; base_url="https://api.anthropic.com"; model="claude-sonnet-4-20250514" ;;
        4) provider="custom"
           read -rp "Base URL: " base_url
           read -rp "Model name: " model
           ;;
        *) echo "Invalid choice, defaulting to OpenRouter."
           provider="openrouter"; base_url="https://openrouter.ai/api/v1"; model="nousresearch/hermes-3-llama-3.1-8b" ;;
    esac

    local signup_hint=""
    case "$provider" in
        openrouter) signup_hint="Get your key at: https://openrouter.ai/keys" ;;
        openai) signup_hint="Get your key at: https://platform.openai.com/api-keys" ;;
        anthropic) signup_hint="Get your key at: https://console.anthropic.com/settings/keys" ;;
    esac

    if [ -n "$signup_hint" ]; then
        echo ""
        echo "$signup_hint"
    fi

    echo ""
    read -rsp "API Key: " api_key
    echo ""

    if [ -z "$api_key" ]; then
        echo "WARNING: No API key provided. You can configure it later."
        return 0
    fi

    echo "[*] Verifying API connection..."
    if $PYTHON_CMD "$SHARED_DIR/verify-llm.py" \
        --provider "$provider" \
        --api-key "$api_key" \
        --base-url "$base_url" \
        --model "$model"; then
        echo "[OK] Connection verified!"
    else
        echo "WARNING: Could not verify connection. Saving config anyway."
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
