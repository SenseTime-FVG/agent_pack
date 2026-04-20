Set-StrictMode -Version Latest
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

# Invoke a bash command inside the user's default WSL distro.  The command
# is passed through base64 so embedded quotes / newlines don't need shell
# escaping on the wsl.exe command line.
#
# The base64 payload is written to a temp file rather than:
#  - inlined into `-lc` (hits the Windows 32,767-char CreateProcess cap —
#    PowerShell 5.1 raises IndexOutOfRangeException once the bash body plus
#    CN mirror preamble pushes past the limit), or
#  - piped via PowerShell stdin (stdin is consumed by base64 and closed, so
#    interactive prompts inside the bash body — e.g. `git clone` asking
#    for a GitHub username on a private repo — see EOF and can't read
#    keyboard input).
# Loading the payload from a file inside WSL keeps the outer bash's stdin
# attached to the console, so prompts work.
function Invoke-WslCommand {
    param([Parameter(Mandatory)][string]$Command)

    $normalizedCommand = $Command -replace "`r`n?", "`n"
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($normalizedCommand))

    $payloadFile = [System.IO.Path]::GetTempFileName()
    try {
        # ASCII: base64 alphabet is 7-bit; avoid a UTF-8 BOM that would
        # corrupt the first decoded byte.
        [System.IO.File]::WriteAllText($payloadFile, $encodedCommand, [System.Text.Encoding]::ASCII)
        $payloadWslPath = Convert-WindowsPathToWslPath -WindowsPath $payloadFile

        # Decode the payload into a temp bash script inside WSL, then run it
        # with `bash <script>` so the script's stdin stays attached to the
        # console (interactive git-credential prompts work).
        #
        # Avoid process substitution `bash <(...)` on the PowerShell side:
        # wsl.exe 5.1 has mishandled Win32 argv strings containing `<(` and
        # trips with "程序"wsl.exe"无法运行: 索引超出了数组界限".  Running
        # the two-step decode + exec inside a single -lc string keeps every
        # argument simple enough for wsl.exe's argv forwarding.
        $bashScript = 'set -euo pipefail; tmp=$(mktemp); trap "rm -f $tmp" EXIT; base64 -d -i "$1" > "$tmp"; bash "$tmp"'
        & wsl.exe -- bash -lc $bashScript _ $payloadWslPath
        if ($LASTEXITCODE -ne 0) {
            throw "WSL command failed in default distro with exit code $LASTEXITCODE."
        }
    } finally {
        Remove-Item -LiteralPath $payloadFile -Force -ErrorAction SilentlyContinue
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
