# Agent Pack

跨平台一键安装器，用于安装 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 和 [OpenClaw](https://github.com/openclaw/openclaw)。

[English README](README.md)

## 功能

- 调用各产品的官方安装脚本，安装 Hermes Agent 和/或 OpenClaw
- 配置 LLM 供应商（OpenRouter、OpenAI、Anthropic 或自定义端点）
- 预置 Sensenova 技能库（已直接放在各产品的 `skills/` 目录中）
- 安装结束后直接在当前窗口拉起 agent，省去手动重启 shell 的步骤

## 工作原理

Agent Pack 是我们所维护的 Hermes Agent 和 OpenClaw 源码（位于 `repos/` 下）的**唯一真相源**。安装时各平台都会从 GitHub 重新克隆本 monorepo（一次克隆、多个产品共享），拷出对应产品子目录，然后以 `--source-ready` 调用产品自带的 `scripts/install.sh`，让它跳过自己的 clone/pull、直接使用刚拷贝出来的源码。运行时依赖（Python、Node.js、uv、git、构建工具）仍由产品自带的安装脚本处理。

```
Step 1: 先一次性收集 LLM 供应商凭据（提前问完所有交互问题）
Step 2: 选择产品 (Hermes / OpenClaw / 两者都要)
Step 3: clone agent_pack（共享一次）、拷出 repos/<product>、运行其 install.sh
        - Hermes:   install.sh --source-ready --skip-setup --dir <target>
        - OpenClaw: install.sh --install-method git --source-ready --git-dir <target> \
                                --no-onboard --no-prompt
Step 4: 每个产品装完后立刻写入它自己的 LLM 配置
        (~/.hermes/config.yaml, ~/.openclaw/openclaw.json；OpenClaw 这边走自己
         的 CLI，同时把用户选的模型注册到 models.providers 里)
Step 5: 在当前窗口直接拉起刚装好的 agent
        - 只装 Hermes：    exec hermes
        - 只装 OpenClaw：  exec openclaw gateway --verbose（顺带在浏览器打开 dashboard）
        - 两个都装：       openclaw gateway 后台运行（日志在 ~/.openclaw/gateway.log），
                          前台交给 hermes，OpenClaw dashboard 自动弹浏览器
```

Bundled skills 已经直接放进 `repos/hermes-agent/skills/` 和 `repos/openclaw/skills/` 中，随产品安装一起完成，无需单独的复制步骤。

提前问完 LLM 配置意味着用户只需要交互一次，之后的长流程安装和最终的 agent 启动都无需看守。每装完一个产品立刻写它的配置，也保证另一个产品失败时已经装好的那个不会没凭据可用。

### 中国区镜像

安装器检测到中国区网络（或设置了 `AGENTPACK_CN=1`）时，会在 clone URL 前加上 GitHub 代理前缀：默认依次尝试 `https://ghproxy.cn/` 和 `https://ghfast.top/`，失败自动切换到下一个。镜像列表可在 `config/defaults.json` 的 `agent_pack.cn_mirrors` 中自定义。

## 平台级前提

平台级前提**不会**自动安装 —— 手动装一次，再运行 Agent Pack 安装器。运行时依赖（Python、Node.js、uv、git、构建工具）**会**由各产品的安装脚本自动处理，无需手动管。

### Windows

需要 **WSL2 + 一个 Linux 发行版**（Inno Setup 安装器底层通过 `wsl.exe` 执行所有操作）。

1. **以管理员身份**打开 PowerShell，运行：
   ```powershell
   wsl --install
   ```
2. 按提示**重启**电脑。
3. 重启后 Windows 会启动新装的 Ubuntu —— 按提示设置 UNIX 用户名和密码。
4. （可选，仅当 `wsl --install` 没有自动选一个发行版时）从 Microsoft Store 装一个，比如 Ubuntu。

参考：<https://learn.microsoft.com/windows/wsl/install>

### macOS

需要 **Xcode Command Line Tools**（提供 `git`、`clang`）和 **Homebrew**（安装器用 `brew install` 拉运行时依赖）。

1. 装 Command Line Tools：
   ```bash
   xcode-select --install
   ```
2. 装 Homebrew（如果 `brew --version` 已经能输出版本号就跳过）：
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. Apple Silicon 机器需要把 brew 加到 shell 启动文件里（安装器内部也会自动 source，但自己 shell 也装一下方便日常使用）：
   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

参考：<https://developer.apple.com/download/all/> · <https://brew.sh>

### Linux

没有需要手动装的前提 —— `apt`/`yum` 相关的依赖安装器自己处理。只需要系统自带的 `bash`、`curl` 和 `sudo`（主流发行版标配）。

## 下载

预编译的安装器发布在 [GitHub Releases 页面](https://github.com/SenseTime-FVG/agent_pack/releases/latest)，挑自己平台的那一个：

| 平台 | 下载 | 使用方式 |
|------|------|---------|
| Windows | [去最新 release 下载 `-windows-x64.exe`](https://github.com/SenseTime-FVG/agent_pack/releases/latest) | 双击运行向导；安装过程在 WSL2 中执行，安装完成后当前 PowerShell 窗口会被接管，直接跑起 agent |
| macOS | [去最新 release 下载 `-macos-universal.pkg`](https://github.com/SenseTime-FVG/agent_pack/releases/latest) | 双击后按图形向导完成产品选择和 LLM 配置；安装完成后会按所选产品自动打开 OpenClaw Gateway Terminal 与 dashboard，并打开 Hermes Terminal |
| Linux | [去最新 release 下载 `-linux.sh`](https://github.com/SenseTime-FVG/agent_pack/releases/latest) 或下面的一行命令 | 下载后 `chmod +x AgentPack-*-linux.sh && ./AgentPack-*-linux.sh`，或直接粘贴 `curl -fsSL https://raw.githubusercontent.com/SenseTime-FVG/agent_pack/main/linux/install.sh \| bash` — 两种方式都会在安装结束后用 `exec` 在当前 shell 里拉起 agent |

## 从源码构建

### Windows (.exe)

需要预先安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。

```powershell
cd windows
iscc installer.iss
```

产物：`dist/AgentPack-<ver>-windows-x64.exe`

### macOS (.pkg)

在 macOS 机器上运行：

```bash
cd macos
./build-pkg.sh
```

产物：`dist/AgentPack-<ver>-macos-universal.pkg`

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
