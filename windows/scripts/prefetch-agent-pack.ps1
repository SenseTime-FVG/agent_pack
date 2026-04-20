# prefetch-agent-pack.ps1 — Clone agent_pack once inside WSL2 so both
# install-hermes.ps1 and install-openclaw.ps1 can copy from the same source
# tree (instead of each cloning independently).
#
# Cache path inside WSL is fixed: $HOME/.agent-pack/.cache/agent_pack.  Both
# install-hermes.ps1 and install-openclaw.ps1 export AGENT_PACK_CACHE_DIR to
# this same path before sourcing the shared fetch helper.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "prefetch-agent-pack"
trap {
    Write-Host ""
    Write-Host "[!] Prefetch failed. Full log: $logPath" -ForegroundColor Red
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
Write-Host "  Pre-fetching agent_pack" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Assert-Wsl2Ready

$isChina = Test-IsChinaRegion
if ($isChina) {
    Write-Ok "Detected China network — using domestic mirrors for git"
}

$appRoot = Get-AgentPackRoot
$sharedDir = Join-Path $appRoot "shared"
$sharedDirWsl = Convert-WindowsPathToWslPath -WindowsPath $sharedDir

$cnFlag = if ($isChina) { "1" } else { "0" }

# Cache location inside WSL — must match the path exported by install-hermes.ps1
# and install-openclaw.ps1.
$command = @"
set -euo pipefail
export AGENTPACK_CN='$cnFlag'
CACHE_DIR="`$HOME/.agent-pack/.cache/agent_pack"
bash "$sharedDirWsl/prefetch-agent-pack.sh" "`$CACHE_DIR"
"@

Invoke-WslCommand -Command $command

Stop-InstallLog
