#!/usr/bin/env bash
# Install OpenClaw by cloning the agent_pack monorepo and delegating to
# repos/openclaw/scripts/install.sh with --install-method git --source-ready.
#
# agent_pack is now the source of truth for our vendored copy of OpenClaw, so
# we install in "git" mode (from our own source tree) rather than from the
# public npm registry.  The old `--install-method npm` path is no longer used.

_AP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_AP_DEFAULTS_JSON="$_AP_ROOT/config/defaults.json"
_AP_FETCH="$_AP_ROOT/shared/fetch-agent-pack.sh"

_openclaw_get() { python3 -c "import json; print(json.load(open('$_AP_DEFAULTS_JSON'))$1)" 2>/dev/null; }

OPENCLAW_INSTALL_DIR_DEFAULT="$(_openclaw_get "['openclaw']['install_dir']")"
OPENCLAW_INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-${OPENCLAW_INSTALL_DIR_DEFAULT//\$HOME/$HOME}}"

install_openclaw() {
    echo ""
    echo "========================================"
    echo "  Installing OpenClaw"
    echo "========================================"

    if [ ! -x "$_AP_FETCH" ]; then
        chmod +x "$_AP_FETCH" 2>/dev/null || true
    fi

    echo "[*] Fetching openclaw source from agent_pack..."
    if ! bash "$_AP_FETCH" "repos/openclaw" "$OPENCLAW_INSTALL_DIR"; then
        echo "[!] ERROR: Failed to fetch openclaw source."
        return 1
    fi

    local install_script="$OPENCLAW_INSTALL_DIR/scripts/install.sh"
    if [ ! -f "$install_script" ]; then
        echo "[!] ERROR: $install_script not found after fetch."
        return 1
    fi

    echo "[*] Running openclaw install.sh (git --source-ready)..."
    # Under WSL, /mnt/<drive> paths are inherited from Windows PATH and every
    # file shows up as executable.  openclaw's install.sh uses `command -v
    # corepack` to detect a corepack binary; if the user has a Windows-side
    # corepack on PATH (e.g. /mnt/d/tools/corepack) it wins, and the Linux
    # kernel can't execute a PE binary, aborting the install with:
    #   cannot execute: required file not found
    # Strip /mnt/* entries from PATH for just this sub-shell to keep the
    # lookup Linux-only.  We only do this under WSL so native Linux installs
    # aren't affected.
    local child_path="$PATH"
    if grep -qi microsoft /proc/version 2>/dev/null; then
        child_path="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd:)"
    fi

    # When hermes installs first it sets npm's global prefix to
    # $HERMES_HOME/node (e.g. /root/.hermes/node).  openclaw then runs
    # `npm install -g pnpm@10` which lands in $prefix/bin — but that dir
    # isn't on PATH, so the subsequent `command -v pnpm` check fails and
    # openclaw aborts with "pnpm installation failed" even though the
    # install succeeded.  Prepend the current global prefix's bin/ to PATH
    # so the follow-up lookup finds pnpm regardless of where hermes put it.
    local npm_prefix=""
    if command -v npm >/dev/null 2>&1; then
        npm_prefix="$(PATH="$child_path" npm config get prefix 2>/dev/null || true)"
    fi
    if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ]; then
        child_path="$npm_prefix/bin:$child_path"
    fi

    # AGENTPACK_VERBOSE=1 propagates to upstream install.sh as OPENCLAW_VERBOSE,
    # which unfolds every run_quiet_step (default behavior hides stdout/stderr
    # unless the step fails, and even then only tail -n 80 is emitted — which
    # has repeatedly hidden real root causes for us).
    local verbose_arg=()
    if [ "${AGENTPACK_VERBOSE:-0}" = "1" ]; then
        verbose_arg=(--verbose)
    fi

    PATH="$child_path" OPENCLAW_VERBOSE="${AGENTPACK_VERBOSE:-0}" \
        bash "$install_script" \
            --install-method git \
            --source-ready \
            --git-dir "$OPENCLAW_INSTALL_DIR" \
            --no-onboard --no-prompt \
            "${verbose_arg[@]}"
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[!] ERROR: OpenClaw installation failed (exit code $rc)."
        return 1
    fi

    # Upstream install.sh demotes `pnpm ui:build` failures to a warning
    # ("UI build failed; continuing (CLI may still work)") and returns 0,
    # which is how we ended up shipping installs where `openclaw gateway`
    # later fails with "Control UI assets not found".  Detect the missing
    # product directly and retry ui:build loudly — if it still fails, fall
    # back to a clear error so the user isn't stuck with a half-working CLI.
    local ui_dist="$OPENCLAW_INSTALL_DIR/dist/control-ui"
    if [ ! -f "$ui_dist/index.html" ]; then
        echo "[!] Control UI assets missing at $ui_dist — retrying ui:build with full output..."

        # Re-locate pnpm from scratch.  $child_path above was computed
        # BEFORE install.sh ran and so doesn't see dirs npm/corepack
        # created during the install (e.g. $npm_prefix/bin, corepack's
        # ~/.local/share/pnpm, etc).  Use `hash -r` to clear bash's
        # negative lookup cache, then fall through a list of well-known
        # install locations.  Mirrors the same belt-and-suspenders
        # approach used for the openclaw binary search below.
        hash -r 2>/dev/null || true
        local retry_path="$child_path"
        # Refresh npm prefix in case the install shuffled it.
        local npm_prefix_now=""
        if command -v npm >/dev/null 2>&1; then
            npm_prefix_now="$(PATH="$retry_path" npm config get prefix 2>/dev/null || true)"
        fi
        local extra
        for extra in \
            "${npm_prefix_now:+$npm_prefix_now/bin}" \
            "$HOME/.local/share/pnpm" \
            "$HOME/.local/bin" \
            "/usr/local/bin" \
            "/usr/bin"; do
            [ -z "$extra" ] && continue
            case ":$retry_path:" in *":$extra:"*) ;; *) retry_path="$extra:$retry_path" ;; esac
        done

        if ! PATH="$retry_path" command -v pnpm >/dev/null 2>&1; then
            echo "[!] ERROR: pnpm not on PATH after install — ui:build cannot retry." >&2
            echo "    Searched: $retry_path" >&2
            echo "    Finish the install manually:" >&2
            echo "      cd $OPENCLAW_INSTALL_DIR && pnpm install && pnpm ui:build && pnpm build" >&2
            return 1
        fi

        if ! ( cd "$OPENCLAW_INSTALL_DIR" && PATH="$retry_path" pnpm ui:build ); then
            echo "[!] ERROR: pnpm ui:build failed. Run with AGENTPACK_VERBOSE=1 to see the dependency install step in full." >&2
            echo "    You can complete the install manually by running:" >&2
            echo "      cd $OPENCLAW_INSTALL_DIR && pnpm install && pnpm ui:build && pnpm build" >&2
            return 1
        fi
    fi

    # Enable local gateway mode unconditionally so `openclaw gateway` works
    # out of the box — even when the user skipped LLM setup (empty API key).
    # Without this, launching the gateway fails with:
    #   Gateway start blocked: set gateway.mode=local (current: unset)
    # `openclaw config set` is idempotent; re-running the installer is safe.
    #
    # Locating the freshly-installed openclaw binary is fiddly: bash caches
    # PATH lookups (`hash`) within the shell, npm's global prefix may differ
    # from the default PATH, and under WSL $child_path has been pruned of
    # /mnt/*.  Build a broad candidate list and take whichever one exists.
    hash -r 2>/dev/null || true
    local openclaw_bin=""
    local cand
    for cand in \
        "$(PATH="$child_path" command -v openclaw 2>/dev/null)" \
        "${npm_prefix:+$npm_prefix/bin/openclaw}" \
        "$HOME/.local/bin/openclaw" \
        "/usr/local/bin/openclaw" \
        "/usr/bin/openclaw"; do
        if [ -n "$cand" ] && [ -x "$cand" ]; then
            openclaw_bin="$cand"
            break
        fi
    done

    if [ -n "$openclaw_bin" ]; then
        if ! PATH="$child_path" "$openclaw_bin" config set gateway.mode local >/dev/null 2>&1; then
            echo "[!] Could not set gateway.mode=local automatically."
            echo "    Run: openclaw config set gateway.mode local"
        fi
    else
        echo "[!] openclaw not found on PATH after install — skipping gateway.mode=local."
        echo "    Run: openclaw config set gateway.mode local"
    fi

    echo "[OK] OpenClaw installed."
}
