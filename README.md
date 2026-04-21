# Agent Pack

Multi-platform one-click installer for [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [OpenClaw](https://github.com/openclaw/openclaw).

[中文 README](README.zh-CN.md)

## What It Does

- Installs Hermes Agent and/or OpenClaw via each product's official installer
- Configures an LLM provider (OpenRouter, OpenAI, Anthropic, or custom)
- Ships with bundled Sensenova skills already placed inside each product's `skills/` directory
- Launches the installed agent(s) automatically when setup finishes — no manual shell-restart step

## How It Works

Agent Pack is the source of truth for its vendored copies of Hermes Agent and OpenClaw (under `repos/`). At install time, each installer clones this monorepo fresh from GitHub (once, shared across products), copies out the relevant subdirectory, and invokes the bundled `scripts/install.sh` with `--source-ready` so it skips its own clone/pull and uses the freshly copied source. Runtime dependencies (Python, Node.js, uv, git, build tools) are still handled by the product installer.

```
Step 1: Collect LLM provider credentials up front (one interactive pass)
Step 2: Select products (Hermes / OpenClaw / Both)
Step 3: Clone agent_pack once, copy out repos/<product>, run its install.sh
        - Hermes:   install.sh --source-ready --skip-setup --dir <target>
        - OpenClaw: install.sh --install-method git --source-ready --git-dir <target> \
                                --no-onboard --no-prompt
Step 4: Write LLM provider config per product immediately after it installs
        (~/.hermes/config.yaml, ~/.openclaw/openclaw.json; OpenClaw is configured
         via its own CLI, which also registers the model under models.providers)
Step 5: Launch the installed agent(s) in the current window
        - Hermes only:   exec hermes
        - OpenClaw only: exec openclaw gateway --verbose (+ opens dashboard in browser)
        - Both:          openclaw gateway runs in the background (log at
                         ~/.openclaw/gateway.log), hermes takes over the foreground,
                         and the OpenClaw dashboard opens in the browser
```

Bundled skills live inside `repos/hermes-agent/skills/` and `repos/openclaw/skills/`, so they are installed as part of each product's normal install — no extra step needed.

The up-front LLM prompt means the user only interacts once; the long-running installs and the final product launch then run unattended. Per-product config is written as soon as each install succeeds, so a later product's failure never strands a working one without credentials.

### China-region mirrors

When the installer detects a China region (or `AGENTPACK_CN=1` is set), it prefixes the clone URL with a GitHub proxy — defaults are `https://ghproxy.cn/` then `https://ghfast.top/`, tried in order on failure. Override the list in `config/defaults.json` under `agent_pack.cn_mirrors`.

## Platform Prerequisites

Platform-level prerequisites are **not** auto-installed — install them manually once, then run the Agent Pack installer. Runtime dependencies (Python, Node.js, uv, git, build tools) **are** auto-installed by the product installers, so you don't need those.

### Windows

Requires **WSL2 + a Linux distro** (the Inno Setup installer calls `wsl.exe` under the hood).

1. Open **PowerShell as Administrator** and run:
   ```powershell
   wsl --install
   ```
2. **Reboot** when prompted.
3. On first boot, Windows launches the new Ubuntu distro — set a UNIX username and password.
4. (Optional, only if `wsl --install` didn't pick one) install a distro from the Microsoft Store, e.g. Ubuntu.

Reference: <https://learn.microsoft.com/windows/wsl/install>

### macOS

Requires **Xcode Command Line Tools** (for `git`, `clang`) and **Homebrew** (used by the installer to `brew install` runtime deps).

1. Install the Command Line Tools:
   ```bash
   xcode-select --install
   ```
2. Install Homebrew (skip if `brew --version` already prints a version):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. On Apple Silicon, add brew to your shell (the installer auto-sources this too, but do it once for your own shell):
   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

References: <https://developer.apple.com/download/all/> · <https://brew.sh>

### Linux

No manual prerequisites — the installer handles `apt`/`yum` dependencies itself. You only need `bash`, `curl`, and `sudo` (standard on every mainstream distro).

## Download

Pre-built installers live on the [GitHub Releases page](https://github.com/SenseTime-FVG/agent_pack/releases/latest). Grab the one for your platform:

| Platform | Download | How to Use |
|----------|----------|------------|
| Windows | [`AgentPack-Setup-1.0.0.exe`](https://github.com/SenseTime-FVG/agent_pack/releases/latest/download/AgentPack-Setup-1.0.0.exe) | Double-click and follow the wizard; installation runs inside WSL2, and the PowerShell window is taken over by the installed agent when setup finishes |
| macOS | [`AgentPack-1.0.0.pkg`](https://github.com/SenseTime-FVG/agent_pack/releases/latest/download/AgentPack-1.0.0.pkg) | Double-click, then complete setup in the Terminal window that opens; the same window becomes the agent's REPL / gateway once installation finishes |
| Linux | bash one-liner | `curl -fsSL https://raw.githubusercontent.com/SenseTime-FVG/agent_pack/main/linux/install.sh \| bash` — the shell that ran the installer is handed over to the agent via `exec` |

## Building from Source

### Windows (.exe)

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php) installed.

```powershell
cd windows
iscc installer.iss
```

Output: `dist/AgentPack-Setup-1.0.0.exe`

### macOS (.pkg)

Run on a macOS machine:

```bash
cd macos
./build-pkg.sh
```

Output: `dist/AgentPack-1.0.0.pkg`

### Linux

No build step needed. Distribute `linux/install.sh` and `linux/lib/` together, or host the full repo and use:

```bash
curl -fsSL https://raw.githubusercontent.com/SenseTime-FVG/agent_pack/main/linux/install.sh | bash
```

## Configuration

All configurable values live in a single file: [`config/defaults.json`](config/defaults.json).

### Bundled Skills

Skills are committed directly to the bundled product repos:

- Hermes: `repos/hermes-agent/skills/` (excludes `system-admin-skill`)
- OpenClaw: `repos/openclaw/skills/` (all skills)

To update the skill set, edit the `skills/` directory of the relevant repo and commit. There is no separate skill-sync step or manifest file.

### Product Install Sources

`config/defaults.json` declares where the vendored source tree is fetched from and where each product gets installed:

```json
"agent_pack": {
  "repo_url": "https://github.com/SenseTime-FVG/agent_pack.git",
  "branch": "main",
  "cn_mirrors": ["https://ghproxy.cn/", "https://ghfast.top/"]
},
"hermes":   { "branch": "main", "install_dir": "$HOME/.agent-pack/repos/hermes-agent" },
"openclaw": {                   "install_dir": "$HOME/.agent-pack/repos/openclaw" }
```

All platforms (Windows, macOS, Linux) clone `agent_pack.repo_url` at install time and copy out `repos/<product>/`. There is no longer a separate "bundled" install path — the Windows `.exe` and macOS `.pkg` bundle only the glue scripts, not the product sources.

### LLM Providers

The installer guides users through provider setup. Provider defaults (name, base URL, default model, signup URL) are read from `config/defaults.json`:

- **OpenRouter** (default) — 200+ models, free tier available
- **OpenAI** — `gpt-4o-mini` default
- **Anthropic** — Claude Sonnet default
- **Custom** — Any OpenAI-compatible endpoint

Resulting config is written to `~/.hermes/config.yaml` and `~/.openclaw/openclaw.json`.

## Project Structure

```text
agent_pack/
|- config/            # Single source of truth: defaults.json (repo URL, mirrors, LLM providers)
|- shared/            # verify-llm.py + fetch-agent-pack.sh (clones agent_pack with CN fallback)
|- repos/             # Vendored hermes-agent and openclaw sources (with skills bundled in)
|- windows/           # Inno Setup installer + PowerShell/WSL bridge scripts
|- macos/             # .pkg builder + pre/postinstall scripts
\- linux/             # Bash installer (install.sh + lib/)
```

## License

MIT
