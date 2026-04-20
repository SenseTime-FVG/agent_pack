# install-openclaw.ps1 - Install OpenClaw inside WSL2.
# Clones agent_pack from GitHub (with CN mirror fallback) and delegates to
# repos/openclaw/scripts/install.sh --install-method git --source-ready,
# then — if LLM parameters were supplied by the wizard — invokes
# apply_llm_config_for in the same WSL session.

param(
    [string]$Provider = "",
    [string]$ApiKey   = "",
    [string]$BaseUrl  = "",
    [string]$Model    = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "install-openclaw"
trap {
    Write-Host ""
    Write-Host "[!] Installation failed. Full log: $logPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "==================== FULL LOG ====================" -ForegroundColor DarkGray
    if (Test-Path $logPath) { Get-Content -LiteralPath $logPath | Write-Host }
    else { Write-Host "[log not found: $logPath]" }
    Write-Host "==================================================" -ForegroundColor DarkGray
    Stop-InstallLog
    Wait-ForKeyIfConsole
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing OpenClaw" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Assert-Wsl2Ready
Write-Ok "Running installer commands inside the default WSL2 distro"

$isChina = Test-IsChinaRegion
if ($isChina) {
    Write-Ok "Detected China network — using domestic mirrors for uv / pip / npm / git"
}

$appRoot = Get-AgentPackRoot
$linuxLibDir = Join-Path $appRoot "linux\lib"
$linuxLibDirWsl = Convert-WindowsPathToWslPath -WindowsPath $linuxLibDir

$mirrorPreamble = Get-CnMirrorBashPreamble
$cnFlag = if ($isChina) { "1" } else { "0" }

$applySnippet = Get-ApplyLlmBashSnippet `
    -Product "openclaw" `
    -Provider $Provider `
    -ApiKey $ApiKey `
    -BaseUrl $BaseUrl `
    -Model $Model

$command = @"
set -euo pipefail
export AGENTPACK_CN='$cnFlag'
export AGENT_PACK_CACHE_DIR="`$HOME/.agent-pack/.cache/agent_pack"
$mirrorPreamble
. "$linuxLibDirWsl/install-openclaw.sh"
install_openclaw
$applySnippet
"@

Invoke-WslCommand -Command $command
New-WslCommandWrappers -Name "openclaw" -LinuxCommand 'openclaw "$@"'

Stop-InstallLog
