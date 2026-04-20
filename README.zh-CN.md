# Agent Pack

跨平台一键安装器，用于安装 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 和 [OpenClaw](https://github.com/openclaw/openclaw)。

[English README](README.md)

## 功能

- 调用各产品的官方安装脚本，安装 Hermes Agent 和/或 OpenClaw
- 配置 LLM 供应商（OpenRouter、OpenAI、Anthropic 或自定义端点）
- 预置 Sensenova 技能库（已直接放在各产品的 `skills/` 目录中）

## 工作原理

两个产品都委托给它们各自的官方 `scripts/install.sh` 来安装。官方脚本会自动处理所有运行时依赖（Python、Node.js、uv、git、构建工具）。Agent Pack 只负责高层次的流程编排：

```
Step 1: 选择产品 (Hermes / OpenClaw / 两者都要)
Step 2: 为每个产品运行官方 install.sh
        - Hermes:   install.sh --skip-setup
        - OpenClaw: install.sh --no-onboard --no-prompt
Step 3: 写入 LLM 供应商配置
        (~/.hermes/config.yaml, ~/.openclaw/openclaw.json)
```

Bundled skills 已经直接放进 `repos/hermes-agent/skills/` 和 `repos/openclaw/skills/` 中，随产品安装一起完成，无需单独的复制步骤。

## 平台级前提

平台级前提不会自动安装；安装器会提示用户自行安装并提供链接。

| 平台 | 前提 | 链接 |
|------|------|------|
| Windows | WSL2 + Linux 发行版 | https://learn.microsoft.com/windows/wsl/install |
| macOS | Xcode Command Line Tools | https://developer.apple.com/download/all/ |
| macOS | Homebrew | https://brew.sh |

运行时依赖（Python、Node.js、uv、git、构建工具）由各产品的官方安装脚本自动安装。

## 下载

| 平台 | 格式 | 使用方式 |
|------|------|---------|
| Windows | `.exe` 安装器 | 双击运行向导；安装过程在 WSL2 中执行 |
| macOS | `.pkg` 安装器 | 双击后在自动打开的 Terminal 窗口中完成安装 |
| Linux | bash 脚本 | `curl -fsSL https://URL/install.sh \| bash` |

## 从源码构建

### Windows (.exe)

需要预先安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。

```powershell
cd windows
iscc installer.iss
```

产物：`dist/AgentPack-Setup-1.0.0.exe`

### macOS (.pkg)

在 macOS 机器上运行：

```bash
cd macos
./build-pkg.sh
```

产物：`dist/AgentPack-1.0.0.pkg`

### Linux

无需构建。可以分发 `linux/install.sh` 加 `linux/lib/` 目录，或者托管整个 repo 然后用：

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/agent-pack/main/linux/install.sh | bash
```

## 配置

所有可配置的值都集中在单一文件中：[`config/defaults.json`](config/defaults.json)。

### Bundled Skills

技能直接提交在各产品的 repo 内：

- Hermes: `repos/hermes-agent/skills/`（排除 `system-admin-skill`）
- OpenClaw: `repos/openclaw/skills/`（包含所有技能）

想要更新技能集，直接编辑对应 repo 的 `skills/` 目录并提交即可。没有单独的同步步骤或 manifest 文件。

### 产品安装源

`config/defaults.json` 保存官方安装脚本的 URL 和 Hermes 的分支：

```json
"hermes": {
  "install_script_url": "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh",
  "branch": "main"
},
"openclaw": {
  "install_script_url": "https://openclaw.ai/install.sh"
}
```

在线安装时直接拉取这些 URL。离线安装（Windows `.exe` / macOS `.pkg`）使用安装包中自带的 `repos/*/scripts/install.sh`。

### LLM 供应商

安装器会引导用户完成供应商配置。供应商的默认值（名称、base URL、默认模型、注册链接）全部从 `config/defaults.json` 读取：

- **OpenRouter**（默认）— 200+ 模型，有免费额度
- **OpenAI** — 默认 `gpt-4o-mini`
- **Anthropic** — 默认 Claude Sonnet
- **Custom** — 任何兼容 OpenAI 的端点

生成的配置会写入 `~/.hermes/config.yaml` 和 `~/.openclaw/openclaw.json`。

## 项目结构

```text
agent_pack/
|- config/            # 唯一的配置来源：defaults.json（URL、LLM 供应商）
|- shared/            # verify-llm.py（API 连通性检查）
|- repos/             # 预克隆的 hermes-agent 和 openclaw，skills 已打包进去
|- windows/           # Inno Setup 安装器 + PowerShell/WSL 桥接脚本
|- macos/             # .pkg 构建器 + pre/postinstall 脚本
\- linux/             # Bash 安装器 (install.sh + lib/)
```

## 许可协议

MIT
