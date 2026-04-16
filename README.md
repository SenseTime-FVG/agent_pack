# Agent Pack

Multi-platform one-click installer for [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [OpenClaw](https://github.com/openclaw/openclaw).

## What It Does

- Installs Hermes Agent and/or OpenClaw with all dependencies
- Configures an LLM provider (OpenRouter, OpenAI, Anthropic, or custom)
- Pre-installs skills from a configurable manifest URL

## Download

| Platform | Format | How to Use |
|----------|--------|------------|
| Windows | `.exe` installer | Double-click and follow the wizard |
| macOS | `.pkg` installer | Double-click, then complete setup in Terminal |
| Linux | bash script | `curl -fsSL https://URL/install.sh \| bash` |

## Building from Source

### Windows (.exe)

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php) installed.

```
cd windows
iscc installer.iss
```

Output: `dist/AgentPack-Setup-1.0.0.exe`

### macOS (.pkg)

Run on a macOS machine:

```
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

### Skill Manifest

Edit `config/defaults.json` to change the `skill_manifest_url` field. The URL should point to a JSON file with this format:

```json
{
  "version": 1,
  "skills": [
    {
      "name": "my-skill",
      "source": "https://skillhub.example.com/skills/my-skill",
      "target": "hermes",
      "required": false
    }
  ]
}
```

`target` can be `"hermes"`, `"openclaw"`, or `"both"`.

### LLM Providers

The installer guides users through provider setup. Supported providers:

- **OpenRouter** (default) — 200+ models, free tier available
- **OpenAI** — GPT-4o-mini default
- **Anthropic** — Claude Sonnet default
- **Custom** — Any OpenAI-compatible endpoint

## Project Structure

```
agent_pack/
├── config/          # Shared configuration files
├── shared/          # Cross-platform Python helper scripts
├── windows/         # Inno Setup installer + PowerShell scripts
├── macos/           # .pkg builder + shell scripts
└── linux/           # Bash installer scripts
```

## License

MIT
