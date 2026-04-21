# install-deps.ps1 - Validate the Windows WSL2 environment for Agent Pack,
# then pre-fetch the agent_pack source tree once so install-hermes.ps1 and
# install-openclaw.ps1 can copy from a shared cache instead of each cloning
# the repo independently.

param(
    [switch]$NeedPython,
    [switch]$NeedNode
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "install-deps"
trap {
    Write-Host ""
    Write-Host "[!] Dependency check failed. Full log: $logPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "==================== FULL LOG ====================" -ForegroundColor DarkGray
    if (Test-Path $logPath) { Get-Content -LiteralPath $logPath | Write-Host }
    else { Write-Host "[log not found: $logPath]" }
    Write-Host "==================================================" -ForegroundColor DarkGray
    try { Stop-Transcript | Out-Null } catch { }
    Wait-ForKeyIfConsole
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Checking Windows Dependencies" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Assert-Wsl2Ready
Write-Ok "WSL2 default distro is reachable"

Invoke-WslCommand -Command 'set -euo pipefail; uname -a >/dev/null'
Write-Ok "WSL shell is ready"

$isChina = Test-IsChinaRegion
if ($isChina) {
    Write-Ok "Detected China network — installer will use domestic mirrors (npm / pip / uv)"
} else {
    Write-Ok "Detected overseas network — using default registries"
}

# ---- Pre-fetch agent_pack (shared cache for per-product installs) ----
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Pre-fetching agent_pack" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$appRoot = Get-AgentPackRoot
$sharedDir = Join-Path $appRoot "shared"
$sharedDirWsl = Convert-WindowsPathToWslPath -WindowsPath $sharedDir
$cnFlag = if ($isChina) { "1" } else { "0" }

# Cache location inside WSL — install-hermes.ps1 and install-openclaw.ps1
# export AGENT_PACK_CACHE_DIR to the same path.
$prefetchCommand = @"
set -euo pipefail
export AGENTPACK_CN='$cnFlag'
CACHE_DIR="`$HOME/.agent-pack/.cache/agent_pack"
bash "$sharedDirWsl/prefetch-agent-pack.sh" "`$CACHE_DIR"
"@

Invoke-WslCommand -Command $prefetchCommand

Stop-InstallLog
