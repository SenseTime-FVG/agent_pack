# install-hermes.ps1 - Install Hermes Agent inside WSL2.
# Clones agent_pack from GitHub (with CN mirror fallback) and delegates to
# repos/hermes-agent/scripts/install.sh --source-ready, then — if LLM
# parameters were supplied by the wizard — invokes apply_llm_config_for in
# the same WSL session so config lands right after install.

param(
    [string]$Provider = "",
    [string]$ApiKey   = "",
    [string]$BaseUrl  = "",
    [string]$Model    = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "install-hermes"
trap {
    Write-Host ""
    Write-Host "[!] Installation failed. Full log: $logPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "==================== FULL LOG ====================" -ForegroundColor DarkGray
    if (Test-Path $logPath) { Get-Content -LiteralPath $logPath | Write-Host }
    else { Write-Host "[log not found: $logPath]" }
    Write-Host "==================================================" -ForegroundColor DarkGray
    Stop-InstallLog
    try {
        $markerDir = Join-Path $env:LOCALAPPDATA "AgentPack\markers"
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $markerDir "hermes-failed.marker") `
            -Value $logPath -Encoding ASCII
    } catch { }
    Wait-ForKeyIfConsole
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing Hermes Agent" -ForegroundColor Cyan
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

# Source the linux library, run install_hermes, then apply the LLM config.
# Doing both in one WSL session means the same AGENTPACK_CN / mirror env
# carries into config verification (`verify-llm.py`) and apply edits the
# freshly-seeded ~/.hermes/config.yaml template.
$applySnippet = Get-ApplyLlmBashSnippet `
    -Product "hermes" `
    -Provider $Provider `
    -ApiKey $ApiKey `
    -BaseUrl $BaseUrl `
    -Model $Model

$command = @"
set -euo pipefail
export AGENTPACK_CN='$cnFlag'
export AGENT_PACK_CACHE_DIR="`$HOME/.agent-pack/.cache/agent_pack"
$mirrorPreamble
. "$linuxLibDirWsl/install-hermes.sh"
install_hermes
$applySnippet
"@

Invoke-WslCommand -Command $command
New-WslCommandWrappers -Name "hermes" -LinuxCommand 'hermes "$@"'

Stop-InstallLog

# Signal the installer that hermes is installed, so CurStepChanged can stop
# polling.  See windows/installer.iss RunInstallScripts for the reader.
$markerDir = Join-Path $env:LOCALAPPDATA "AgentPack\markers"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $markerDir "hermes-installed.marker") `
    -Value ([DateTime]::UtcNow.ToString("o")) -Encoding ASCII

# Hand the current console over to the hermes REPL.  We don't return —
# Inno Setup spawned us with ewNoWait, so this window is ours to keep.
# The user Ctrl-D / Ctrl-C's hermes themselves when they're done.
Write-Host ""
Write-Host "[OK] Hermes Agent installed. Starting hermes in this window..." -ForegroundColor Green
Write-Host ""
& wsl.exe -- bash -lc 'hermes'
