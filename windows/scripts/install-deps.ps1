# install-deps.ps1 — Detect and install Python 3.11, Node.js 22, uv, git
# Called by Inno Setup during installation.
# Parameters: -NeedPython -NeedNode (switches)

param(
    [switch]$NeedPython,
    [switch]$NeedNode
)

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }

# --- Git ---
function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Ok "git $(git --version)"
        return
    }
    Write-Step "Installing git via winget..."
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Ok "git installed"
}

# --- Python 3.11 ---
function Install-Python {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $ver = & python --version 2>&1
        if ($ver -match "3\.11") {
            Write-Ok "Python $ver"
            return
        }
    }
    $py311 = Get-Command python3.11 -ErrorAction SilentlyContinue
    if ($py311) {
        Write-Ok "python3.11 found"
        return
    }

    Write-Step "Installing Python 3.11 via winget..."
    winget install --id Python.Python.3.11 -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Ok "Python 3.11 installed"
}

# --- uv ---
function Install-Uv {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Ok "uv $(uv --version)"
        return
    }
    Write-Step "Installing uv..."
    irm https://astral.sh/uv/install.ps1 | iex
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    Write-Ok "uv installed"
}

# --- Node.js 22 ---
function Install-Node {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $ver = (node -v) -replace 'v', ''
        $major = [int]($ver.Split('.')[0])
        if ($major -ge 22) {
            Write-Ok "Node.js v$ver"
            return
        }
    }
    Write-Step "Installing Node.js 22 via winget..."
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Ok "Node.js installed"
}

# --- Main ---
Install-Git

if ($NeedPython) {
    Install-Python
    Install-Uv
}

if ($NeedNode) {
    Install-Node
}

Write-Host ""
Write-Ok "All dependencies ready."
