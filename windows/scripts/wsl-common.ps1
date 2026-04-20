Set-StrictMode -Version Latest
$script:WslQueryError = ""
$script:RegionChecked = $false
$script:IsChinaRegion = $false

# CN mirrors — shared with linux/lib/*.sh so user experience is consistent
$script:CnNpmRegistry = "https://registry.npmmirror.com"
$script:CnPipIndex = "https://mirrors.aliyun.com/pypi/simple/"
$script:CnUvPythonMirror = "https://registry.npmmirror.com/-/binary/python-build-standalone"
$script:GitHubProxies = @("https://gh-proxy.com/", "https://ghfast.top/", "https://mirror.ghproxy.com/")

function Get-AgentPackLogDir {
    $logDir = Join-Path $env:LOCALAPPDATA "AgentPack\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    return $logDir
}

function Start-InstallLog {
    param([Parameter(Mandatory)][string]$Name)

    $logDir = Get-AgentPackLogDir
    $logPath = Join-Path $logDir "$Name.log"
    try {
        Start-Transcript -Path $logPath -Force | Out-Null
    } catch {
        Write-Warning "Could not start transcript at $logPath: $_"
    }
    Write-Host "[log] Writing install log to: $logPath" -ForegroundColor DarkGray
    return $logPath
}

function Stop-InstallLog {
    try { Stop-Transcript | Out-Null } catch { }
}

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Get-AgentPackRoot {
    $parent = Split-Path -Parent $PSScriptRoot
    if ((Test-Path (Join-Path $parent "linux\lib")) -and (Test-Path (Join-Path $parent "config"))) {
        return $parent
    }

    $grandParent = Split-Path -Parent $parent
    if ($grandParent -and (Test-Path (Join-Path $grandParent "linux\lib")) -and (Test-Path (Join-Path $grandParent "config"))) {
        return $grandParent
    }

    return $parent
}

function Get-WslDistros {
    $script:WslQueryError = ""
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        $script:WslQueryError = "wsl.exe was not found."
        return @()
    }

    # wsl.exe emits UTF-16 LE (little-endian) to stdout. PowerShell decodes
    # child-process output using [Console]::OutputEncoding, which defaults to
    # the system ANSI codepage (e.g. GBK on zh-CN Windows) — that mangles the
    # output into garbage that looks like ASCII interleaved with NULs but is
    # actually double-width misdecoded bytes.  Force Unicode for this call.
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $output = & wsl.exe --list --verbose 2>&1
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }

    if ($LASTEXITCODE -ne 0) {
        $script:WslQueryError = "wsl.exe --list --verbose failed."
        return @()
    }

    if (-not $output) {
        $script:WslQueryError = "No WSL distro information was returned."
        return @()
    }

    $distros = @()
    foreach ($line in $output) {
        # Strip BOM / stray NULs that may survive the encoding swap, plus any
        # trailing CR left over from the Windows console.
        $clean = ($line -replace "[`u{0000}`u{FEFF}]", "").Trim()
        if (-not $clean) {
            continue
        }

        if ($clean -match "^(?<default>\*)?\s*(?<name>\S.*?)\s{2,}\S+\s{2,}(?<version>\d+)\s*$") {
            $distros += [pscustomobject]@{
                Name      = $Matches.name.Trim()
                Version   = [int]$Matches.version
                IsDefault = ($Matches.default -eq "*")
            }
        }
    }

    return $distros
}

function Get-PreferredWslDistro {
    $distros = Get-WslDistros
    if (-not $distros) {
        return $null
    }

    $default = $distros | Where-Object { $_.IsDefault } | Select-Object -First 1
    if ($default -and $default.Version -eq 2) {
        return $default
    }

    return $distros | Where-Object { $_.Version -eq 2 } | Select-Object -First 1
}

function Assert-Wsl2Ready {
    $installUrl = "https://learn.microsoft.com/windows/wsl/install"

    $distros = Get-WslDistros
    if (-not $distros) {
        if ($script:WslQueryError -eq "wsl.exe was not found.") {
            Write-Host ""
            Write-Host "========================================================" -ForegroundColor Red
            Write-Host "  WSL2 is required but not installed on this system." -ForegroundColor Red
            Write-Host "========================================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Please install WSL2 using one of the following methods:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Option 1 - Run in PowerShell (Admin):" -ForegroundColor White
            Write-Host "    wsl --install" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Option 2 - Follow the guide:" -ForegroundColor White
            Write-Host "    $installUrl" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  After installation and reboot, re-run the Agent Pack installer." -ForegroundColor Yellow
            Write-Host ""
            throw "WSL2 is required. Install guide: $installUrl"
        }
        if ($script:WslQueryError -eq "wsl.exe --list --verbose failed.") {
            Write-Host ""
            Write-Host "========================================================" -ForegroundColor Red
            Write-Host "  WSL is installed but could not be queried." -ForegroundColor Red
            Write-Host "========================================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "  WSL may need to be initialized or updated." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Try running in PowerShell (Admin):" -ForegroundColor White
            Write-Host "    wsl --update" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  More info: $installUrl" -ForegroundColor Cyan
            Write-Host ""
            throw "WSL query failed. See: $installUrl"
        }
        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host "  No WSL Linux distribution found." -ForegroundColor Red
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  WSL is installed but no Linux distro is available." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Install a distro by running in PowerShell (Admin):" -ForegroundColor White
        Write-Host "    wsl --install -d Ubuntu" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Or install from Microsoft Store:" -ForegroundColor White
        Write-Host "    https://aka.ms/wslstore" -ForegroundColor Cyan
        Write-Host ""
        throw "No WSL distro found. Install guide: $installUrl"
    }

    $chosen = Get-PreferredWslDistro
    if (-not $chosen) {
        $names = ($distros | ForEach-Object { "$($_.Name) (v$($_.Version))" }) -join ", "
        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host "  No WSL version 2 distro found." -ForegroundColor Red
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Current distros (all version 1): $names" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Upgrade an existing distro to version 2:" -ForegroundColor White
        Write-Host "    wsl --set-version <DistroName> 2" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Or install a new WSL2 distro:" -ForegroundColor White
        Write-Host "    wsl --install -d Ubuntu" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  More info: $installUrl" -ForegroundColor Cyan
        Write-Host ""
        throw "No WSL2 distro available. Install guide: $installUrl"
    }

    return $chosen
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$Command
    )

    $normalizedCommand = $Command -replace "`r`n?", "`n"
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($normalizedCommand))
    $bashCommand = "printf '%s' '$encodedCommand' | base64 -d | bash"

    & wsl.exe -d $Distro -- bash -lc $bashCommand
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed in distro '$Distro' with exit code $LASTEXITCODE."
    }
}

function Convert-WindowsPathToWslPath {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$WindowsPath
    )

    $fullWindowsPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $normalizedWindowsPath = $fullWindowsPath -replace "\\", "/"
    $bashSingleQuoteEscape = "'" + '"' + "'" + '"' + "'"
    $escapedWindowsPath = $normalizedWindowsPath.Replace("'", $bashSingleQuoteEscape)
    $bashCommand = "wslpath -a -- '$escapedWindowsPath'"

    $converted = & wsl.exe -d $Distro -- bash -lc $bashCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to convert Windows path '$WindowsPath' to a WSL path."
    }

    return ($converted | Select-Object -Last 1).Trim()
}

function Get-WslHomePath {
    param([Parameter(Mandatory)][string]$Distro)

    $home = & wsl.exe -d $Distro -- bash -lc 'printf %s "$HOME"'
    if ($LASTEXITCODE -ne 0 -or -not $home) {
        throw "Failed to determine the WSL home directory for '$Distro'."
    }

    return ($home | Select-Object -Last 1).Trim()
}

function Get-WslUncPath {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$LinuxPath
    )

    $trimmed = $LinuxPath.Trim()
    if (-not $trimmed.StartsWith("/")) {
        throw "Expected a Linux path starting with '/': $LinuxPath"
    }

    $suffix = $trimmed.TrimStart("/") -replace "/", "\"
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        return "\\wsl$\$Distro"
    }

    return "\\wsl$\$Distro\$suffix"
}

function Get-WslHomeUncPath {
    param([Parameter(Mandatory)][string]$Distro)

    return Get-WslUncPath -Distro $Distro -LinuxPath (Get-WslHomePath -Distro $Distro)
}

function Test-IsChinaRegion {
    # Cached per-session to avoid repeated network calls.  Explicit override via
    # AGENTPACK_CN=1/0 skips detection entirely (useful for CI / VPN users).
    if ($script:RegionChecked) {
        return $script:IsChinaRegion
    }

    $override = $env:AGENTPACK_CN
    if ($override) {
        $script:IsChinaRegion = ($override -eq "1" -or $override -ieq "true")
        $script:RegionChecked = $true
        return $script:IsChinaRegion
    }

    try {
        $resp = Invoke-RestMethod -Uri "https://api.iping.cc/v1/query" -TimeoutSec 5 -ErrorAction Stop
        $script:IsChinaRegion = ($resp.country_code -eq "CN")
    } catch {
        $script:IsChinaRegion = $false
    }
    $script:RegionChecked = $true
    return $script:IsChinaRegion
}

function Get-CnMirrorBashPreamble {
    # Bash snippet that exports standard env vars honored by uv / pip / npm /
    # curl inside WSL.  Prepend to any WSL command that installs dependencies.
    # No-op (empty string) when not in a China region.
    if (-not (Test-IsChinaRegion)) {
        return ""
    }

    return @"
export UV_INDEX_URL='$script:CnPipIndex'
export UV_DEFAULT_INDEX='$script:CnPipIndex'
export PIP_INDEX_URL='$script:CnPipIndex'
export UV_PYTHON_INSTALL_MIRROR='$script:CnUvPythonMirror'
export npm_config_registry='$script:CnNpmRegistry'
"@
}

function Resolve-GitHubRawUrl {
    # When in a China region, prepend a GitHub raw-content proxy so curl | bash
    # of official install scripts (astral.sh -> GitHub, hermes/openclaw raw
    # files) succeeds.  Falls through unchanged for non-github.com URLs.
    param([Parameter(Mandatory)][string]$Url)

    if (-not (Test-IsChinaRegion)) {
        return $Url
    }
    if ($Url -notmatch '^https?://(raw\.githubusercontent\.com|github\.com|objects\.githubusercontent\.com)/') {
        return $Url
    }
    return $script:GitHubProxies[0] + $Url
}

function New-WslCommandWrappers {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$LinuxCommand
    )

    $wrapperDir = Join-Path $env:LOCALAPPDATA "AgentPack\bin"
    New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null

    $ps1Path = Join-Path $wrapperDir "$Name.ps1"
    $cmdPath = Join-Path $wrapperDir "$Name.cmd"
    $cmdLinuxCommand = $LinuxCommand.Replace('"', '\"')

    @"
param(
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$Arguments
)

`$invokeArgs = @('-d', '$Distro', '--', 'bash', '-lc', '$LinuxCommand', 'bash') + `$Arguments
& wsl.exe @invokeArgs
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $ps1Path -Encoding UTF8

    @"
@echo off
setlocal
wsl.exe -d "$Distro" -- bash -lc "$cmdLinuxCommand" bash %*
exit /b %errorlevel%
"@ | Set-Content -LiteralPath $cmdPath -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$wrapperDir*") {
        try {
            [Environment]::SetEnvironmentVariable("Path", "$wrapperDir;$userPath", "User")
        } catch {
            Write-Warn "Could not update the user PATH automatically. Launchers are still available in $wrapperDir."
        }
    }

    Write-Ok "Created WSL launcher wrapper: $cmdPath"
}
