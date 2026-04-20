# install-openclaw.ps1 - Install OpenClaw inside WSL2 using the official installer.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "install-openclaw"
trap {
    Write-Host ""
    Write-Host "[!] Installation failed. Full log: $logPath" -ForegroundColor Red
    Stop-InstallLog
    break
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing OpenClaw" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$distro = Assert-Wsl2Ready
Write-Ok "Running installer commands inside WSL2 distro '$($distro.Name)'"
if (Test-IsChinaRegion) {
    Write-Ok "Detected China network — using domestic mirrors for uv / pip / npm"
}
$appRoot = Get-AgentPackRoot
$reposDir = Join-Path $appRoot "repos\openclaw"
$reposDirWsl = Convert-WindowsPathToWslPath -Distro $distro.Name -WindowsPath $reposDir

# The bundled repo contains the official scripts/install.sh which handles
# dependency detection, installation, PATH setup, and config templating.
#
# We deliberately use --install-method npm (not git):
#   - Inno Setup's [Files] section does not bundle .git directories, so the
#     bundled checkout cannot be used as a git work tree.
#   - npm mode installs from the npm registry and does not require a local
#     checkout or .git metadata.
# We still invoke the bundled install.sh so the installer semantics track the
# version we ship.  --no-onboard --no-prompt skips the interactive wizard so
# Agent Pack's own LLM configuration step runs instead.
$mirrorPreamble = Get-CnMirrorBashPreamble
$command = @"
set -euo pipefail
$mirrorPreamble
bash "$reposDirWsl/scripts/install.sh" --install-method npm --no-onboard --no-prompt
"@

Invoke-WslCommand -Distro $distro.Name -Command $command
New-WslCommandWrappers -Name "openclaw" -Distro $distro.Name -LinuxCommand 'openclaw "$@"'

Stop-InstallLog
