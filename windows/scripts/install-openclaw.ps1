# install-openclaw.ps1 — Install OpenClaw via npm

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing OpenClaw" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "[*] Installing OpenClaw via npm..." -ForegroundColor Cyan
npm install -g openclaw@latest

$OpenClawConfig = "$env:USERPROFILE\.openclaw"
New-Item -ItemType Directory -Path $OpenClawConfig -Force | Out-Null

if (-not (Test-Path "$OpenClawConfig\openclaw.json")) {
    @'
{
  "agent": {
    "model": ""
  }
}
'@ | Set-Content "$OpenClawConfig\openclaw.json" -Encoding UTF8
}

Write-Host "[OK] OpenClaw installed." -ForegroundColor Green
