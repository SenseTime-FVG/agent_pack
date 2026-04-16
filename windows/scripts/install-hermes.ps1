# install-hermes.ps1 — Clone and set up Hermes Agent
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\hermes-agent"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing Hermes Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$HermesConfig = "$env:USERPROFILE\.hermes"

if (Test-Path "$InstallDir\.git") {
    Write-Host "[*] Updating existing installation..." -ForegroundColor Cyan
    Push-Location $InstallDir
    git stash -q 2>$null
    git pull -q origin main
    Pop-Location
} else {
    Write-Host "[*] Cloning Hermes Agent..." -ForegroundColor Cyan
    git clone -q https://github.com/NousResearch/hermes-agent.git $InstallDir
}

Push-Location $InstallDir

Write-Host "[*] Creating virtual environment..." -ForegroundColor Cyan
try {
    uv venv venv --python 3.11
} catch {
    python -m venv venv
}

Write-Host "[*] Installing dependencies (this may take a few minutes)..." -ForegroundColor Cyan
& "$InstallDir\venv\Scripts\activate.ps1"
try {
    uv pip install -e ".[all]"
} catch {
    pip install -e ".[all]"
}
deactivate

Pop-Location

# Create wrapper batch file
$wrapperDir = "$env:LOCALAPPDATA\AgentPack\bin"
New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
@"
@echo off
call "$InstallDir\venv\Scripts\activate.bat"
python -m hermes %*
"@ | Set-Content "$wrapperDir\hermes.cmd" -Encoding UTF8

# Add to user PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$wrapperDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$wrapperDir;$userPath", "User")
}

# Create config directory
New-Item -ItemType Directory -Path $HermesConfig -Force | Out-Null

Write-Host "[OK] Hermes Agent installed." -ForegroundColor Green
