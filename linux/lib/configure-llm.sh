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
# Use ":=" so that callers who pre-populated these (e.g. Windows's
# install-hermes.ps1 passing LLM_* via the WSL bash body) are preserved.
: "${LLM_PROVIDER:=}"
: "${LLM_BASE_URL:=}"
: "${LLM_MODEL:=}"
: "${LLM_API_KEY:=}"

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

    local provider base_url default_model
    case "$choice" in
        1) provider="openrouter"
           base_url="$(_cfg "['llm_providers']['openrouter']['base_url']")"
           default_model="$(_cfg "['llm_providers']['openrouter']['default_model']")"
           ;;
        2) provider="openai"
           base_url="$(_cfg "['llm_providers']['openai']['base_url']")"
           default_model="$(_cfg "['llm_providers']['openai']['default_model']")"
           ;;
        3) provider="anthropic"
           base_url="$(_cfg "['llm_providers']['anthropic']['base_url']")"
           default_model="$(_cfg "['llm_providers']['anthropic']['default_model']")"
           ;;
        4) provider="custom"
           read -rp "Base URL: " base_url
           default_model=""
           ;;
        *) echo "Invalid choice, defaulting to OpenRouter."
           provider="openrouter"
           base_url="$(_cfg "['llm_providers']['openrouter']['base_url']")"
           default_model="$(_cfg "['llm_providers']['openrouter']['default_model']")"
           ;;
    esac

    # Model ID: let the user override the default (e.g. "gpt-4o" instead of
    # "gpt-4o-mini", a specific OpenRouter route, a custom MiniMax id).  We
    # intentionally accept any free-form string and don't whitelist — both
    # Hermes and OpenClaw will surface a clear error at runtime if the id
    # isn't recognized by the provider.  For custom endpoints we require a
    # value (provider catalogs don't cover it); for bundled ones the default
    # is usable out of the box.
    local model=""
    echo ""
    if [ "$provider" = "custom" ]; then
        while [ -z "$model" ]; do
            read -rp "Model name (required for custom endpoint): " model
            model="$(printf '%s' "$model" | tr -d '[:space:]')"
        done
    else
        read -rp "Model ID [$default_model]: " model
        model="${model:-$default_model}"
    fi

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

# Called once per session (first time apply_llm_config_for runs).  Tracks
# state so re-calling for a second product doesn't re-verify the same key.
_LLM_VERIFIED_THIS_SESSION=0
_llm_verify_once() {
    if [ "$_LLM_VERIFIED_THIS_SESSION" -eq 1 ]; then
        return 0
    fi
    _LLM_VERIFIED_THIS_SESSION=1

    local python_cmd="${PYTHON_CMD:-python3}"
    if command -v "$python_cmd" &>/dev/null && [ -f "$SHARED_DIR/verify-llm.py" ]; then
        echo "[*] Verifying API connection..."
        if "$python_cmd" "$SHARED_DIR/verify-llm.py" \
            --provider "$LLM_PROVIDER" \
            --api-key "$LLM_API_KEY" \
            --base-url "$LLM_BASE_URL" \
            --model "$LLM_MODEL"; then
            echo "[OK] Connection verified!"
        else
            echo "WARNING: Could not verify connection. Saving config anyway."
        fi
    fi
}

# Write LLM config for a single product.  Intended to be called immediately
# after that product's install.sh succeeds, so config lands even if a later
# product fails to install.  Idempotent — safe to call more than once with
# the same collected LLM_* values.
apply_llm_config_for() {
    local prod="$1"
    local provider="$LLM_PROVIDER"
    local base_url="$LLM_BASE_URL"
    local model="$LLM_MODEL"
    local api_key="$LLM_API_KEY"

    if [ -z "$api_key" ]; then
        echo "[!] No API key collected — skipping $prod config write."
        return 0
    fi

    # Belt-and-suspenders: fill empty base_url / model from defaults.json so
    # callers that forget to pass them (e.g. an older Windows wizard that
    # only forwarded -BaseUrl for custom) don't write schema-invalid config.
    # OpenClaw rejects models.providers.<name>.baseUrl="" with "Too small:
    # expected string to have >=1 character" — this prevents the CLI call
    # from blowing up the whole install.
    if [ -z "$base_url" ] && [ "$provider" != "custom" ]; then
        base_url="$(_cfg "['llm_providers']['$provider']['base_url']")"
    fi
    if [ -z "$model" ] && [ "$provider" != "custom" ]; then
        model="$(_cfg "['llm_providers']['$provider']['default_model']")"
    fi

    _llm_verify_once

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

            # Patch config.yaml's model block in place.  The template uses
            # 2-space indent under `model:`; we target those keys specifically
            # to avoid touching identically-named keys in commented sections.
            local cfg="$HOME/.hermes/config.yaml"
            if [ -f "$cfg" ]; then
                python3 - "$cfg" "$provider" "$model" "$base_url" << 'PY'
import re, sys
path, provider, model, base_url = sys.argv[1:5]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

def patch_key(src, key, value):
    pattern = re.compile(
        r'(?m)^(?P<indent>  )(?P<key>' + re.escape(key) + r')\s*:\s*(?P<val>.*)$'
    )
    replaced = {'done': False}
    def repl(m):
        if replaced['done']:
            return m.group(0)
        replaced['done'] = True
        return f'{m.group("indent")}{m.group("key")}: "{value}"'
    return pattern.sub(repl, src, count=1)

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
            # openclaw.json has a strict zod schema — we cannot hand-roll it
            # safely (an earlier version of this function wrote bogus top-
            # level keys and bricked `openclaw gateway` with "Unrecognized
            # keys").  Use the CLI for model selection; let openclaw's
            # bundled provider definitions supply baseUrl/endpoints; and put
            # the API key in ~/.openclaw/.env, which openclaw auto-loads
            # (see src/infra/dotenv.ts: loadDotEnv).
            # For bundled providers (openrouter/openai/anthropic) openclaw
            # already knows baseUrl + model list, so `<prefix>/<model>`
            # resolves via the built-in registry.  For custom endpoints we
            # must register a provider entry with the user's baseUrl and
            # the specific model id, otherwise openclaw throws
            # "Unknown model: <prefix>/<model>" at gateway warmup.
            # We keep the custom-provider name literally "custom" to avoid
            # clashing with the bundled "openai" provider.
            local provider_prefix
            case "$provider" in
                openrouter) provider_prefix="openrouter" ;;
                openai)     provider_prefix="openai"     ;;
                anthropic)  provider_prefix="anthropic"  ;;
                custom)     provider_prefix="custom"     ;;
                *)          provider_prefix="openai"     ;;
            esac

            local env_key
            case "$provider" in
                openrouter) env_key="OPENROUTER_API_KEY" ;;
                openai)     env_key="OPENAI_API_KEY"     ;;
                anthropic)  env_key="ANTHROPIC_API_KEY"  ;;
                custom)     env_key="OPENAI_API_KEY"     ;;
                *)          env_key="OPENROUTER_API_KEY" ;;
            esac

            mkdir -p "$HOME/.openclaw"
            local env_file="$HOME/.openclaw/.env"
            touch "$env_file"
            chmod 600 "$env_file" 2>/dev/null || true
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
            echo "[OK] OpenClaw API key saved to ~/.openclaw/.env ($env_key)"

            # Clear bash's PATH-lookup cache: openclaw was just installed
            # by install_openclaw in the same shell, but an earlier failed
            # lookup may have cached a negative result.
            hash -r 2>/dev/null || true
            if ! command -v openclaw >/dev/null 2>&1; then
                echo "[!] openclaw CLI not on PATH — skipping model default."
                echo "    Run 'openclaw config set agents.defaults.model \"${provider_prefix}/${model}\"' after launching a new shell."
                return 0
            fi

            # `openclaw config set` refuses to run if openclaw.json fails
            # schema validation (e.g. stale bad writes from earlier installer
            # versions).  `openclaw config file` prints "Config invalid"
            # before the file path in that case — exit stays 0, so we detect
            # the string explicitly.  On invalid, back the file up so the
            # next `set` re-seeds a valid minimal one.
            local cfg="$HOME/.openclaw/openclaw.json"
            if [ -f "$cfg" ]; then
                if openclaw config file 2>&1 | grep -q "Config invalid"; then
                    echo "[*] Existing openclaw.json is invalid; backing up to openclaw.json.bak and resetting."
                    mv "$cfg" "$cfg.bak" 2>/dev/null || rm -f "$cfg"
                fi
            fi

            # openclaw resolves <prefix>/<model> via its model registry:
            # bundled providers know a fixed catalog (openrouter/openai/
            # anthropic's official model IDs) and will throw "Unknown model"
            # if the user picks a variant that isn't in that catalog —
            # e.g. MiniMax, Moonshot, or any OpenAI-compatible third-party
            # that routes through an OpenAI-shaped endpoint.  To keep the
            # installer predictable for ALL four provider options we register
            # the user's exact model id under models.providers.<prefix>.
            # This overrides bundled entries where they exist and creates
            # one where they don't.
            local api_dialect
            case "$provider" in
                anthropic) api_dialect="anthropic-messages" ;;
                *)         api_dialect="openai-completions" ;;
            esac

            # ModelDefinitionConfig has several required fields (reasoning,
            # input, cost, contextWindow, maxTokens) that earlier installs
            # omitted — openclaw's zod schema rejected the write silently for
            # custom providers, leaving the provider registered but empty and
            # forcing `agents.defaults.model` to fall back to the bundled
            # catalog (which is why users who picked e.g. a Sensenova model
            # saw it vanish from the UI and gateway pick a different agent).
            # Give sensible conservative defaults so the write succeeds; the
            # user can still tweak them later with `openclaw config set`.
            local provider_json
            provider_json="$(
                BASE_URL="$base_url" API_KEY="$api_key" MODEL="$model" API="$api_dialect" \
                python3 -c '
import json, os
print(json.dumps({
    "baseUrl": os.environ["BASE_URL"],
    "apiKey": os.environ["API_KEY"],
    "api": os.environ["API"],
    "models": [{
        "id": os.environ["MODEL"],
        "name": os.environ["MODEL"],
        "api": os.environ["API"],
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 128000,
        "maxTokens": 8192,
    }],
}))
')"
            # Keep stderr visible — a silent rejection here is exactly what
            # caused the Sensenova / custom-provider regression we just fixed.
            if ! openclaw config set "models.providers.${provider_prefix}" \
                    "$provider_json" --strict-json; then
                echo "[!] ERROR: 'openclaw config set models.providers.${provider_prefix}' failed."
                echo "    Config not written; see error above." >&2
                return 1
            fi
            echo "[OK] OpenClaw provider registered: ${provider_prefix} -> ${model} (${api_dialect})"

            # Use `openclaw models set` rather than `config set agents.defaults.model`:
            # `models set` also:
            #   - upserts agents.defaults.models[<key>] (the allowlist the
            #     control UI / session resolver reads)
            #   - canonicalizes the key via the alias index
            #   - handles provider/model vs. legacy string forms
            # Without this, the UI's chat-model dropdown silently falls back
            # to a bundled default (e.g. openai/gpt-4o-mini) because the raw
            # "provider/model" string isn't in the allowlist.
            #
            # We intentionally DO NOT redirect stderr to /dev/null — a silent
            # rejection here previously let an earlier "default model" setting
            # stick even though the user had just picked a new one.
            if ! openclaw models set "${provider_prefix}/${model}"; then
                echo "[!] 'openclaw models set' failed — falling back to 'config set agents.defaults.model'."
                echo "    The allowlist (agents.defaults.models[<key>]) will NOT contain the entry," >&2
                echo "    so the control UI may still show a different default." >&2
                # Fallback: older openclaw builds, or models that fail the
                # alias-index resolve.  At least the primary field gets set.
                openclaw config set agents.defaults.model "${provider_prefix}/${model}"
                echo "[OK] OpenClaw default model set (via 'config set' fallback)"
            else
                echo "[OK] OpenClaw default model set: ${provider_prefix}/${model}"
            fi
            # Note: gateway.mode=local is set unconditionally by
            # install-openclaw.sh right after install, so it works even when
            # the user skipped LLM setup.
            ;;
    esac
}

# Batch helper kept for callers that wait until all installs are done
# (e.g. the old single-step flow, or dry-run testing).  New code should
# call apply_llm_config_for inside the install loop instead.
apply_llm_config() {
    for prod in "$@"; do
        apply_llm_config_for "$prod"
    done
}

# Back-compat wrapper: old callers (macOS setup-interactive.sh) still invoke
# configure_llm as a single collect+apply step.  install.sh now calls
# collect_llm_config up front and apply_llm_config after products install.
configure_llm() {
    collect_llm_config
    apply_llm_config "$@"
}
