#!/usr/bin/env bash
# Interactive LLM provider configuration.
# Provider details (base_url, default_model, signup_url) are read from
# config/defaults.json so there is a single source of truth.
#
# Split into two phases (mirrors the Windows installer wizard):
#   collect_llm_config  — prompt the user up front; exports LLM_* vars.
#   apply_llm_config    — after products install, write config files and
#                         verify the API.  Safe to skip writing if the user
#                         opted out (empty key).
# This lets install.sh collect credentials BEFORE any install runs, so
# product install failures don't block the user from having a usable config.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../../shared" && pwd)"
_DEFAULTS_JSON="$(cd "$SCRIPT_DIR/../.." && pwd)/config/defaults.json"

# Helper: read a value from defaults.json
_cfg() { python3 -c "import json; print(json.load(open('$_DEFAULTS_JSON'))$1)" 2>/dev/null; }

# Exported by collect_llm_config, consumed by apply_llm_config.
LLM_PROVIDER=""
LLM_BASE_URL=""
LLM_MODEL=""
LLM_API_KEY=""

collect_llm_config() {
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
    local api_key
    read -rsp "API Key: " api_key
    echo ""

    LLM_PROVIDER="$provider"
    LLM_BASE_URL="$base_url"
    LLM_MODEL="$model"
    LLM_API_KEY="$api_key"
}

apply_llm_config() {
    local products=("$@")
    local provider="$LLM_PROVIDER"
    local base_url="$LLM_BASE_URL"
    local model="$LLM_MODEL"
    local api_key="$LLM_API_KEY"

    echo ""
    echo "========================================"
    echo "  Writing LLM Configuration"
    echo "========================================"

    if [ -z "$api_key" ]; then
        echo "WARNING: No API key was provided earlier. Skipping config write."
        echo "         Re-run the installer or edit ~/.hermes/.env / ~/.openclaw/openclaw.json manually."
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
                # Hermes config layout:
                #   ~/.hermes/config.yaml — structured template (model.provider,
                #     model.default, model.base_url).  Hermes install.sh already
                #     seeded this from cli-config.yaml.example; we only edit
                #     the three keys in place so the rest of the template
                #     (comments, unrelated sections) survives.
                #   ~/.hermes/.env        — API keys, picked up at runtime.
                # Previously we wrote a flat top-level YAML here, which hermes
                # couldn't parse — the agent fell back to its auto-detect path
                # with no credentials.
                mkdir -p "$HOME/.hermes"

                local env_key
                case "$provider" in
                    openrouter) env_key="OPENROUTER_API_KEY" ;;
                    openai)     env_key="OPENAI_API_KEY"     ;;
                    anthropic)  env_key="ANTHROPIC_API_KEY"  ;;
                    custom)     env_key="OPENAI_API_KEY"     ;;
                    *)          env_key="OPENROUTER_API_KEY" ;;
                esac

                local env_file="$HOME/.hermes/.env"
                touch "$env_file"
                chmod 600 "$env_file" 2>/dev/null || true
                # Drop prior entries for the keys we're about to write so
                # re-running the installer doesn't leave stale duplicates.
                local keys_to_replace="$env_key"
                if [ "$provider" = "custom" ]; then
                    keys_to_replace="$env_key OPENAI_BASE_URL"
                fi
                for k in $keys_to_replace; do
                    sed -i.bak "/^${k}=/d" "$env_file" 2>/dev/null || true
                done
                rm -f "$env_file.bak" 2>/dev/null || true
                printf '%s=%s\n' "$env_key" "$api_key" >> "$env_file"
                if [ "$provider" = "custom" ]; then
                    printf 'OPENAI_BASE_URL=%s\n' "$base_url" >> "$env_file"
                fi

                # Patch config.yaml's model block in place.  The template
                # uses 2-space indent under `model:`; we target those keys
                # specifically to avoid touching identically-named keys in
                # other (commented) sections.
                local cfg="$HOME/.hermes/config.yaml"
                if [ -f "$cfg" ]; then
                    python3 - "$cfg" "$provider" "$model" "$base_url" << 'PY'
import re, sys
path, provider, model, base_url = sys.argv[1:5]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

def patch_key(src, key, value):
    # Replace `  <key>: "..."` only on its first occurrence inside the
    # top-level `model:` block, leaving comments and other sections alone.
    pattern = re.compile(
        r'(?m)^(?P<indent>  )(?P<key>' + re.escape(key) + r')\s*:\s*(?P<val>.*)$'
    )
    replaced = {'done': False}
    def repl(m):
        if replaced['done']:
            return m.group(0)
        replaced['done'] = True
        return f'{m.group("indent")}{m.group("key")}: "{value}"'
    new = pattern.sub(repl, src, count=1)
    return new

text = patch_key(text, 'default', model)
text = patch_key(text, 'provider', provider)
text = patch_key(text, 'base_url', base_url)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
PY
                    echo "[OK] Hermes config patched at ~/.hermes/config.yaml"
                else
                    echo "[!] ~/.hermes/config.yaml not found — API key saved to .env but model/provider not set."
                fi
                echo "[OK] Hermes API key saved to ~/.hermes/.env ($env_key)"
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

# Back-compat wrapper: old callers (macOS setup-interactive.sh) still invoke
# configure_llm as a single collect+apply step.  install.sh now calls
# collect_llm_config up front and apply_llm_config after products install.
configure_llm() {
    collect_llm_config
    apply_llm_config "$@"
}
