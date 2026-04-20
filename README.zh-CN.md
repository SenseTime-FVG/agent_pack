# Agent Pack

跨平台一键安装器，用于安装 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 和 [OpenClaw](https://github.com/openclaw/openclaw)。

[English README](README.md)

## 功能

- 调用各产品的官方安装脚本，安装 Hermes Agent 和/或 OpenClaw
- 配置 LLM 供应商（OpenRouter、OpenAI、Anthropic 或自定义端点）
- 预置 Sensenova 技能库（已直接放在各产品的 `skills/` 目录中）

## 工作原理

Agent Pack 是我们所维护的 Hermes Agent 和 OpenClaw 源码（位于 `repos/` 下）的**唯一真相源**。安装时各平台都会从 GitHub 重新克隆本 monorepo，拷出对应产品子目录，然后以 `--source-ready` 调用产品自带的 `scripts/install.sh`，让它跳过自己的 clone/pull、直接使用刚拷贝出来的源码。运行时依赖（Python、Node.js、uv、git、构建工具）仍由产品自带的安装脚本处理。

```
Step 1: 选择产品 (Hermes / OpenClaw / 两者都要)
Step 2: clone agent_pack、拷出 repos/<product>、运行其 install.sh
        - Hermes:   install.sh --source-ready --skip-setup --dir <target>
        - OpenClaw: install.sh --install-method git --source-ready --git-dir <target> \
                                --no-onboard --no-prompt
Step 3: 写入 LLM 供应商配置
        (~/.hermes/config.yaml, ~/.openclaw/openclaw.json)
```

Bundled skills 已经直接放进 `repos/hermes-agent/skills/` 和 `repos/openclaw/skills/` 中，随产品安装一起完成，无需单独的复制步骤。

### 中国区镜像

安装器检测到中国区网络（或设置了 `AGENTPACK_CN=1`）时，会在 clone URL 前加上 GitHub 代理前缀：默认依次尝试 `https://ghproxy.cn/` 和 `https://ghfast.top/`，失败自动切换到下一个。镜像列表可在 `config/defaults.json` 的 `agent_pack.cn_mirrors` 中自定义。

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
curl -fsSL https://raw.githubusercontent.com/SenseTime-FVG/agent_pack/main/linux/install.sh | bash
```

## 配置

所有可配置的值都集中在单一文件中：[`config/defaults.json`](config/defaults.json)。

### Bundled Skills

技能直接提交在各产品的 repo 内：

- Hermes: `repos/hermes-agent/skills/`（排除 `system-admin-skill`）
- OpenClaw: `repos/openclaw/skills/`（包含所有技能）

想要更新技能集，直接编辑对应 repo 的 `skills/` 目录并提交即可。没有单独的同步步骤或 manifest 文件。

### 产品安装源

`config/defaults.json` 声明 vendored 源码从哪里拉取、每个产品装到哪：

```json
"agent_pack": {
  "repo_url": "https://github.com/SenseTime-FVG/agent_pack.git",
  "branch": "main",
  "cn_mirrors": ["https://ghproxy.cn/", "https://ghfast.top/"]
},
"hermes":   { "branch": "main", "install_dir": "$HOME/.agent-pack/repos/hermes-agent" },
"openclaw": {                   "install_dir": "$HOME/.agent-pack/repos/openclaw" }
```

所有平台（Windows/macOS/Linux）都会在安装时 clone `agent_pack.repo_url`，再拷出 `repos/<product>/`。已经不再有"离线安装"这条独立路径——Windows `.exe` 和 macOS `.pkg` 只打包胶水脚本，不再打包产品源码。

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
|- config/            # 唯一的配置来源：defaults.json（仓库 URL、镜像、LLM 供应商）
|- shared/            # verify-llm.py + fetch-agent-pack.sh（克隆 agent_pack，CN 自动 fallback）
|- repos/             # Vendored hermes-agent 和 openclaw 源码（skills 一并包含）
|- windows/           # Inno Setup 安装器 + PowerShell/WSL 桥接脚本
|- macos/             # .pkg 构建器 + pre/postinstall 脚本
\- linux/             # Bash 安装器 (install.sh + lib/)
```

## 许可协议

MIT
