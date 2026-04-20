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
    Stop-InstallLog
    break
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Checking Windows Dependencies" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$distro = Assert-Wsl2Ready
Write-Ok "Using WSL distro '$($distro.Name)' (version $($distro.Version))"

Invoke-WslCommand -Distro $distro.Name -Command 'set -euo pipefail; uname -a >/dev/null'
Write-Ok "WSL shell is ready"

if (Test-IsChinaRegion) {
    Write-Ok "Detected China network — installer will use domestic mirrors (npm / pip / uv)"
} else {
    Write-Ok "Detected overseas network — using default registries"
}

Stop-InstallLog
