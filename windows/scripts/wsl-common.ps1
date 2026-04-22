Set-StrictMode -Version Latest

# Force UTF-8 for console I/O.  Windows PowerShell 5.x defaults to GBK (936)
# on zh-CN hosts, which mangles the Chinese strings in our install-*.ps1
# messages and also corrupts stdout captured from WSL commands that emit
# UTF-8.  Setting both Input and OutputEncoding to 65001 applies to every
# script that dot-sources this file (all four install-*.ps1 do).  This is a
# no-op on PowerShell 7+, which already defaults to UTF-8.
try {
    [System.Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(65001)
    [System.Console]::InputEncoding = [System.Text.Encoding]::GetEncoding(65001)
} catch {
    # Some hosts (e.g. Inno Setup's hidden console) can't mutate encoding —
    # ignore the failure rather than aborting the install.
}

$script:RegionChecked = $false
$script:IsChinaRegion = $false

# CN mirrors — shared with linux/lib/*.sh so user experience is consistent.
# GitHub proxies used by the source-tree fetch helper live in
# config/defaults.json (agent_pack.cn_mirrors), not here.
$script:CnNpmRegistry = "https://registry.npmmirror.com"
$script:CnPipIndex = "https://mirrors.aliyun.com/pypi/simple/"
$script:CnUvPythonMirror = "https://registry.npmmirror.com/-/binary/python-build-standalone"

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
        Write-Warning "Could not start transcript at ${logPath}: $_"
    }
    Write-Host "[log] Writing install log to: $logPath" -ForegroundColor DarkGray
    return $logPath
}

function Stop-InstallLog {
    try { Stop-Transcript | Out-Null } catch { }
}

# Keep the child console window open so the user can read the log when the
# installer runs a script in a fresh cmd.exe window.  Inno Setup launches these
# with `powershell.exe -File` directly (no cmd /k wrapper), so the window
# closes as soon as the script exits — unless the script itself pauses.
# Call this at the end of the script on failure paths (usually inside `trap`)
# so successful runs don't block the overall installer flow.
function Wait-ForKeyIfConsole {
    param([string]$Message = "Press Enter to close this window...")
    if ([Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost') {
        Write-Host ""
        Write-Host $Message -ForegroundColor Yellow
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch {
            # RawUI may not be available (e.g. redirected stdin); fall back.
            try { [void](Read-Host) } catch { }
        }
    }
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

# Verify WSL2 is installed and the user's default distro is reachable.
# We intentionally do NOT enumerate distros via `wsl --list --verbose` —
# its UTF-16 output is unreliably decoded by PowerShell 5.1 on zh-CN systems
# (empirically observed truncating "Ubuntu" to "bnt").  Instead we simply run
# a smoke command in the default distro; if WSL is missing or the default
# distro can't launch, wsl.exe returns a non-zero exit code and we surface
# the matching install guidance.
function Assert-Wsl2Ready {
    $installUrl = "https://learn.microsoft.com/windows/wsl/install"

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host "  WSL2 is required but not installed on this system." -ForegroundColor Red
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Install WSL2 with (PowerShell as Administrator):" -ForegroundColor White
        Write-Host "    wsl --install" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Guide: $installUrl" -ForegroundColor Cyan
        Write-Host ""
        throw "WSL2 is required. Install guide: $installUrl"
    }

    # Smoke test: run a trivial command in the default distro.
    # We don't pass -d: the user's default distro is what we target.
    # Piping `$null` into wsl.exe avoids rare "device not ready" stdin issues.
    $null | & wsl.exe -- bash -lc 'echo agent-pack-ready' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host "  WSL2 is installed but the default distro is not ready." -ForegroundColor Red
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Try one of these in PowerShell (Administrator):" -ForegroundColor White
        Write-Host "    wsl --update" -ForegroundColor Cyan
        Write-Host "    wsl --install -d Ubuntu       # if no distro is installed" -ForegroundColor Cyan
        Write-Host "    wsl --set-default <DistroName>  # if the default is a v1 distro" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Then re-run the Agent Pack installer." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Guide: $installUrl" -ForegroundColor Cyan
        Write-Host ""
        throw "WSL2 default distro is not reachable (wsl exit $LASTEXITCODE). See: $installUrl"
    }
}

# Invoke a bash command inside the user's default WSL distro.
#
# The bash body is written to a Windows temp file as UTF-8 (LF line
# endings, no BOM) and executed via `wsl.exe -- bash <wslpath>`.  We
# deliberately avoid every alternative:
#   - `bash -lc <long-string>` hits Windows' 32,767-char CreateProcess cap
#     once the body plus CN mirror preamble grows; PowerShell 5.1 then
#     raises IndexOutOfRangeException ("索引超出了数组界限").
#   - Piping the script via PowerShell stdin closes stdin for any nested
#     interactive prompt (e.g. `git clone` asking for credentials).
#   - A base64 + `bash -lc 'decode | bash'` orchestrator trips wsl.exe's
#     argv parser: `$(...)` inside the orchestrator string is mangled
#     (command substitution result goes missing), which silently breaks
#     things like `tmp=$(mktemp)`.
# Running a plain file path as bash's only argument keeps every special
# character inside the file, where bash — not wsl.exe — parses it.
function Invoke-WslCommand {
    param([Parameter(Mandatory)][string]$Command)

    $normalizedCommand = $Command -replace "`r`n?", "`n"

    $scriptFile = [System.IO.Path]::GetTempFileName()
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($scriptFile, $normalizedCommand, $utf8NoBom)
        $scriptWslPath = Convert-WindowsPathToWslPath -WindowsPath $scriptFile

        & wsl.exe -- bash $scriptWslPath
        if ($LASTEXITCODE -ne 0) {
            throw "WSL command failed in default distro with exit code $LASTEXITCODE."
        }
    } finally {
        Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue
    }
}

function Convert-WindowsPathToWslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $fullWindowsPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $normalizedWindowsPath = $fullWindowsPath -replace "\\", "/"
    $bashSingleQuoteEscape = "'" + '"' + "'" + '"' + "'"
    $escapedWindowsPath = $normalizedWindowsPath.Replace("'", $bashSingleQuoteEscape)
    $bashCommand = "wslpath -a -- '$escapedWindowsPath'"

    $converted = & wsl.exe -- bash -lc $bashCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to convert Windows path '$WindowsPath' to a WSL path."
    }

    return ($converted | Select-Object -Last 1).Trim()
}

function Get-WslHomePath {
    $wslHome = & wsl.exe -- bash -lc 'printf %s "$HOME"'
    if ($LASTEXITCODE -ne 0 -or -not $wslHome) {
        throw "Failed to determine the WSL home directory."
    }

    return ($wslHome | Select-Object -Last 1).Trim()
}

# Resolve a Linux path in the default WSL distro to a Windows UNC path by
# asking WSL itself (`wslpath -w`).  This avoids having to know the distro
# name to build `\\wsl$\<distro>\...` manually.
function Get-WslHomeUncPath {
    $unc = & wsl.exe -- bash -lc 'wslpath -w -- "$HOME"'
    if ($LASTEXITCODE -ne 0 -or -not $unc) {
        throw "Failed to resolve the WSL home directory as a Windows path."
    }

    return ($unc | Select-Object -Last 1).Trim()
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
    # Bash snippet that (a) sources shared/cn-env.sh inside the agent_pack
    # clone already present on disk, (b) invokes apply_cn_env to set uv /
    # pip / npm mirrors, switch apt to TUNA (Ubuntu only, supported
    # codenames only), and pre-install uv via ghproxy.
    #
    # Prepend to any WSL command that installs dependencies.  No-op (empty
    # string) when not in a China region.
    if (-not (Test-IsChinaRegion)) {
        return ""
    }

    $appRoot = Get-AgentPackRoot
    $sharedDir = Join-Path $appRoot "shared"
    if (-not (Test-Path (Join-Path $sharedDir "cn-env.sh"))) {
        # Fallback: set mirror env vars inline if cn-env.sh is missing for
        # some reason (older checkouts).  No apt/uv handling in that case.
        return @"
export AGENTPACK_CN=1
export UV_INDEX_URL='$script:CnPipIndex'
export UV_DEFAULT_INDEX='$script:CnPipIndex'
export PIP_INDEX_URL='$script:CnPipIndex'
export UV_PYTHON_INSTALL_MIRROR='$script:CnUvPythonMirror'
export npm_config_registry='$script:CnNpmRegistry'
"@
    }

    $sharedDirWsl = Convert-WindowsPathToWslPath -WindowsPath $sharedDir
    return @"
export AGENTPACK_CN=1
. "$sharedDirWsl/cn-env.sh"
apply_cn_env
"@
}

function ConvertTo-BashSingleQuoted {
    # Safely embed a user-supplied string in a bash single-quoted literal.
    # '  ->  '"'"'
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { $Value = "" }
    $esc = "'" + '"' + "'" + '"' + "'"
    return "'" + $Value.Replace("'", $esc) + "'"
}

function Get-ApplyLlmBashSnippet {
    # Build the bash snippet that sources linux/lib/configure-llm.sh, fills
    # the LLM_* vars from the wizard, and calls apply_llm_config_for <prod>.
    # Returns "" when no API key was provided — caller should skip it.
    param(
        [Parameter(Mandatory)][string]$Product,
        [string]$Provider,
        [string]$ApiKey,
        [string]$BaseUrl,
        [string]$Model
    )

    if (-not $ApiKey) { return "" }

    $appRoot = Get-AgentPackRoot
    $linuxLibDir = Join-Path $appRoot "linux\lib"
    $linuxLibDirWsl = Convert-WindowsPathToWslPath -WindowsPath $linuxLibDir

    $qProvider = ConvertTo-BashSingleQuoted $Provider
    $qApiKey   = ConvertTo-BashSingleQuoted $ApiKey
    $qBaseUrl  = ConvertTo-BashSingleQuoted $BaseUrl
    $qModel    = ConvertTo-BashSingleQuoted $Model
    $qProduct  = ConvertTo-BashSingleQuoted $Product

    return @"
. "$linuxLibDirWsl/configure-llm.sh"
LLM_PROVIDER=$qProvider
LLM_API_KEY=$qApiKey
LLM_BASE_URL=$qBaseUrl
LLM_MODEL=$qModel
apply_llm_config_for $qProduct
"@
}

# Create .cmd + .ps1 launchers that invoke a command inside the user's
# default WSL distro.  We deliberately don't hardcode a distro name so the
# launcher keeps working even if the user later switches default distros.
function New-WslCommandWrappers {
    param(
        [Parameter(Mandatory)][string]$Name,
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

`$invokeArgs = @('--', 'bash', '-lc', '$LinuxCommand', 'bash') + `$Arguments
& wsl.exe @invokeArgs
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $ps1Path -Encoding UTF8

    @"
@echo off
setlocal
wsl.exe -- bash -lc "$cmdLinuxCommand" bash %*
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
