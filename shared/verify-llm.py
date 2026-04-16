#!/usr/bin/env python3
"""Verify LLM API connectivity. Exit 0 on success, 1 on failure.

Usage:
    python verify-llm.py --provider openrouter --api-key sk-xxx [--base-url URL] [--model MODEL]
"""
import argparse
import json
import sys
import urllib.request
import urllib.error

PROVIDERS = {
    "openrouter": {
        "base_url": "https://openrouter.ai/api/v1",
        "default_model": "nousresearch/hermes-3-llama-3.1-8b",
    },
    "openai": {
        "base_url": "https://api.openai.com/v1",
        "default_model": "gpt-4o-mini",
    },
    "anthropic": {
        "base_url": "https://api.anthropic.com",
        "default_model": "claude-sonnet-4-20250514",
    },
}


def verify_openai_compatible(base_url: str, api_key: str, model: str) -> bool:
    """Verify connectivity for OpenAI-compatible APIs (OpenRouter, OpenAI, custom)."""
    url = f"{base_url.rstrip('/')}/chat/completions"
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": "Say OK"}],
        "max_tokens": 5,
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return "choices" in data
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return False


def verify_anthropic(base_url: str, api_key: str, model: str) -> bool:
    """Verify connectivity for the Anthropic Messages API."""
    url = f"{base_url.rstrip('/')}/v1/messages"
    payload = json.dumps({
        "model": model,
        "max_tokens": 5,
        "messages": [{"role": "user", "content": "Say OK"}],
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return "content" in data
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Verify LLM API connectivity")
    parser.add_argument("--provider", required=True, choices=["openrouter", "openai", "anthropic", "custom"])
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--base-url", default="")
    parser.add_argument("--model", default="")
    args = parser.parse_args()

    provider_info = PROVIDERS.get(args.provider, {})
    base_url = args.base_url or provider_info.get("base_url", "")
    model = args.model or provider_info.get("default_model", "")

    if not base_url:
        print("ERROR: --base-url required for custom provider", file=sys.stderr)
        sys.exit(1)
    if not model:
        print("ERROR: --model required for custom provider", file=sys.stderr)
        sys.exit(1)

    print(f"Verifying {args.provider} API at {base_url} with model {model}...")

    if args.provider == "anthropic":
        ok = verify_anthropic(base_url, args.api_key, model)
    else:
        ok = verify_openai_compatible(base_url, args.api_key, model)

    if ok:
        print("OK: LLM API connection verified successfully.")
        sys.exit(0)
    else:
        print("FAIL: Could not verify LLM API connection.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
