# install-hermes.ps1 - Install Hermes Agent inside WSL2 using the official installer.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$logPath = Start-InstallLog -Name "install-hermes"
trap {
    Write-Host ""
    Write-Host "[!] Installation failed. Full log: $logPath" -ForegroundColor Red
    Stop-InstallLog
    break
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing Hermes Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$distro = Assert-Wsl2Ready
Write-Ok "Running installer commands inside WSL2 distro '$($distro.Name)'"
if (Test-IsChinaRegion) {
    Write-Ok "Detected China network — using domestic mirrors for uv / pip / npm"
}
$appRoot = Get-AgentPackRoot
$reposDir = Join-Path $appRoot "repos\hermes-agent"
$reposDirWsl = Convert-WindowsPathToWslPath -Distro $distro.Name -WindowsPath $reposDir

# The bundled repo contains the official scripts/install.sh which handles
# all dependency detection (uv, Python, git, Node.js), venv creation,
# pip install, PATH setup, and config templating.
# We pass --skip-setup so Agent Pack's own LLM configuration step runs instead.
$mirrorPreamble = Get-CnMirrorBashPreamble
$command = @"
set -euo pipefail
$mirrorPreamble
target_dir="`$HOME/.hermes/hermes-agent"
if [ -d "`$target_dir" ]; then
    rm -rf "`$target_dir"
fi
mkdir -p "`$(dirname "`$target_dir")"
cp -a "$reposDirWsl" "`$target_dir"
bash "`$target_dir/scripts/install.sh" --skip-setup --dir "`$target_dir"
"@

Invoke-WslCommand -Distro $distro.Name -Command $command
New-WslCommandWrappers -Name "hermes" -Distro $distro.Name -LinuxCommand 'hermes "$@"'

Stop-InstallLog
