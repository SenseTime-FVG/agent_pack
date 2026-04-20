# install-hermes.ps1 - Install Hermes Agent inside WSL2.
# Clones agent_pack from GitHub (with CN mirror fallback) and delegates to
# repos/hermes-agent/scripts/install.sh --source-ready.

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

# Source the linux library and call install_hermes.  AGENTPACK_CN tells the
# shared fetch helper whether to try CN mirrors.
$command = @"
set -euo pipefail
export AGENTPACK_CN='$cnFlag'
$mirrorPreamble
. "$linuxLibDirWsl/install-hermes.sh"
install_hermes
"@

Invoke-WslCommand -Command $command
New-WslCommandWrappers -Name "hermes" -LinuxCommand 'hermes "$@"'

Stop-InstallLog
