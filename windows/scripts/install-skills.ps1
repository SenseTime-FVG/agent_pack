# install-skills.ps1 — Fetch and install skills from manifest

param(
    [Parameter(Mandatory)][string[]]$Products,
    [string]$SharedDir = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Installing Skills" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$fetchScript = if ($SharedDir) { "$SharedDir\fetch-skills.py" } else { "" }
if (-not $fetchScript -or -not (Test-Path $fetchScript)) {
    Write-Host "[!] Skill fetch script not found, skipping." -ForegroundColor Yellow
    return
}

foreach ($prod in $Products) {
    Write-Host "[*] Fetching skills for $prod..." -ForegroundColor Cyan
    & python $fetchScript --product $prod
}
