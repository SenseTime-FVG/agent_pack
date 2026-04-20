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
    try {
        $markerDir = Join-Path $env:LOCALAPPDATA "AgentPack\markers"
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $markerDir "openclaw-failed.marker") `
            -Value $logPath -Encoding ASCII
    } catch { }
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

# Signal the installer that openclaw is installed, so CurStepChanged can stop
# polling.  See windows/installer.iss RunInstallScripts for the reader.
$markerDir = Join-Path $env:LOCALAPPDATA "AgentPack\markers"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $markerDir "openclaw-installed.marker") `
    -Value ([DateTime]::UtcNow.ToString("o")) -Encoding ASCII

# Schedule `openclaw dashboard` in a detached Start-Process so the control
# UI opens in the user's default Windows browser a few seconds after the
# gateway binds.  We call it with --no-open (gateway runs inside WSL, where
# `wslview` isn't installed by default) to just get the URL, then use
# Start-Process on the Windows side to open the real browser.
$dashboardScript = @'
param([string]$Script)
Start-Sleep -Seconds 3
try {
    $out = & wsl.exe -- bash -lc 'openclaw dashboard --no-open 2>/dev/null' 2>$null
    $url = $null
    foreach ($line in $out) {
        if ($line -match 'Dashboard URL:\s*(\S+)') {
            $url = $Matches[1]
            break
        }
    }
    if ($url) {
        Start-Process $url
    }
} catch { }
'@
$tmpPs = [System.IO.Path]::GetTempFileName() + ".ps1"
Set-Content -LiteralPath $tmpPs -Value $dashboardScript -Encoding UTF8
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$tmpPs `
    -WindowStyle Hidden | Out-Null

# Hand the current console over to `openclaw gateway --verbose`.  We don't
# return — Inno Setup spawned us with ewNoWait, so this window is ours to
# keep.  The user Ctrl-C's the gateway themselves when they're done.
Write-Host ""
Write-Host "[OK] OpenClaw installed. Starting gateway in this window..." -ForegroundColor Green
Write-Host "[*] Opening OpenClaw dashboard in your browser shortly..." -ForegroundColor Cyan
Write-Host ""
& wsl.exe -- bash -lc 'openclaw gateway --verbose'
