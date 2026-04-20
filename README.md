# Agent Pack

Multi-platform one-click installer for [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [OpenClaw](https://github.com/openclaw/openclaw).

[中文 README](README.zh-CN.md)

## What It Does

- Installs Hermes Agent and/or OpenClaw via each product's official installer
- Configures an LLM provider (OpenRouter, OpenAI, Anthropic, or custom)
- Ships with bundled Sensenova skills already placed inside each product's `skills/` directory

## How It Works

Both products are installed by delegating to their own official `scripts/install.sh`, which handles all runtime dependencies (Python, Node.js, uv, git, build tools) on its own. Agent Pack only coordinates the high-level flow:

```
Step 1: Select products (Hermes / OpenClaw / Both)
Step 2: Run official install.sh for each product
        - Hermes:   install.sh --skip-setup
        - OpenClaw: install.sh --no-onboard --no-prompt
Step 3: Write LLM provider config (~/.hermes/config.yaml, ~/.openclaw/openclaw.json)
```

Bundled skills live inside `repos/hermes-agent/skills/` and `repos/openclaw/skills/`, so they are installed as part of each product's normal install — no extra step needed.

## Platform Prerequisites

Platform-level prerequisites are NOT auto-installed; the installer prompts the user to install them manually with a link.

| Platform | Prerequisite | Link |
|----------|--------------|------|
| Windows | WSL2 + a Linux distro | https://learn.microsoft.com/windows/wsl/install |
| macOS | Xcode Command Line Tools | https://developer.apple.com/download/all/ |
| macOS | Homebrew | https://brew.sh |

Runtime dependencies (Python, Node.js, uv, git, build tools) are auto-installed by the product installers.

## Download

| Platform | Format | How to Use |
|----------|--------|------------|
| Windows | `.exe` installer | Double-click and follow the wizard; installation runs inside WSL2 |
| macOS | `.pkg` installer | Double-click, then complete setup in the Terminal window that opens |
| Linux | bash script | `curl -fsSL https://URL/install.sh \| bash` |

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
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/agent-pack/main/linux/install.sh | bash
```

## Configuration

All configurable values live in a single file: [`config/defaults.json`](config/defaults.json).

### Bundled Skills

Skills are committed directly to the bundled product repos:

- Hermes: `repos/hermes-agent/skills/` (excludes `system-admin-skill`)
- OpenClaw: `repos/openclaw/skills/` (all skills)

To update the skill set, edit the `skills/` directory of the relevant repo and commit. There is no separate skill-sync step or manifest file.

### Product Install Sources

`config/defaults.json` holds the official install-script URLs and the Hermes branch:

```json
"hermes": {
  "install_script_url": "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh",
  "branch": "main"
},
"openclaw": {
  "install_script_url": "https://openclaw.ai/install.sh"
}
```

Online installs fetch these URLs directly. Bundled installs (Windows `.exe` / macOS `.pkg`) use the pre-cloned `repos/*/scripts/install.sh` included in the package.

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
|- config/            # Single source of truth: defaults.json (URLs, LLM providers)
|- shared/            # verify-llm.py (API-connectivity check)
|- repos/             # Pre-cloned hermes-agent and openclaw, with skills bundled in
|- windows/           # Inno Setup installer + PowerShell/WSL bridge scripts
|- macos/             # .pkg builder + pre/postinstall scripts
\- linux/             # Bash installer (install.sh + lib/)
```

## License

MIT
