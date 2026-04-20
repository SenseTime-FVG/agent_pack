# install-deps.ps1 - Validate the Windows WSL2 environment for Agent Pack.

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

if (Test-IsChinaRegion) {
    Write-Ok "Detected China network — installer will use domestic mirrors (npm / pip / uv)"
} else {
    Write-Ok "Detected overseas network — using default registries"
}

Stop-InstallLog
