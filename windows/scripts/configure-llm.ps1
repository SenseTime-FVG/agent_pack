# configure-llm.ps1 - Persist installer-selected LLM settings into the selected WSL2 distro.

param(
    [Parameter(Mandatory)][string]$Provider,
    [Parameter(Mandatory)][string]$ApiKey,
    [string]$BaseUrl = "",
    [string]$Model = "",
    [switch]$Hermes,
    [switch]$OpenClaw,
    [string]$SharedDir = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\wsl-common.ps1"

$Provider = $Provider.Trim().ToLowerInvariant()

$defaults = @{
    "openrouter" = @{ base_url = "https://openrouter.ai/api/v1"; model = "nousresearch/hermes-3-llama-3.1-8b" }
    "openai"     = @{ base_url = "https://api.openai.com/v1"; model = "gpt-4o-mini" }
    "anthropic"  = @{ base_url = "https://api.anthropic.com"; model = "claude-sonnet-4-20250514" }
}

if ($defaults.ContainsKey($Provider)) {
    $BaseUrl = $defaults[$Provider].base_url
    if (-not $Model) {
        $Model = $defaults[$Provider].model
    }
}

function ConvertTo-BashSingleQuoted {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }

    $bashSingleQuoteEscape = "'" + '"' + "'" + '"' + "'"
    return "'" + $Value.Replace("'", $bashSingleQuoteEscape) + "'"
}

function ConvertTo-YamlSingleQuoted {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-DotEnvValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", "").Replace("`n", '\n')
    return '"' + $escaped + '"'
}

function Set-DotEnvValues {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values,
        [string[]]$KeyOrder = @()
    )

    $existingLines = @()
    if (Test-Path -LiteralPath $Path) {
        $existingLines = Get-Content -LiteralPath $Path
    }

    $written = @{}
    $newLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $existingLines) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
            $key = $Matches[1]
            if ($Values.ContainsKey($key)) {
                if (-not $written.ContainsKey($key)) {
                    $newLines.Add($key + "=" + (ConvertTo-DotEnvValue $Values[$key]))
                    $written[$key] = $true
                }
                continue
            }
        }

        $newLines.Add($line)
    }

    $keysToAppend = if ($KeyOrder.Count -gt 0) { $KeyOrder } else { $Values.Keys }
    foreach ($key in $keysToAppend) {
        if ($Values.ContainsKey($key) -and -not $written.ContainsKey($key)) {
            $newLines.Add($key + "=" + (ConvertTo-DotEnvValue $Values[$key]))
        }
    }

    [System.IO.File]::WriteAllText(
        $Path,
        [string]::Join("`n", $newLines) + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Test-WslCommandExists {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$CommandName
    )

    & wsl.exe -d $Distro -- bash -lc "command -v $CommandName >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Get-HermesEnvValues {
    param(
        [Parameter(Mandatory)][string]$SelectedProvider,
        [Parameter(Mandatory)][string]$SelectedApiKey,
        [Parameter(Mandatory)][string]$SelectedBaseUrl
    )

    $values = @{
        "OPENROUTER_API_KEY" = ""
        "OPENAI_API_KEY"     = ""
        "OPENAI_BASE_URL"    = ""
        "ANTHROPIC_API_KEY"  = ""
    }

    switch ($SelectedProvider) {
        "openrouter" {
            $values["OPENROUTER_API_KEY"] = $SelectedApiKey
        }
        "openai" {
            $values["OPENAI_API_KEY"] = $SelectedApiKey
        }
        "anthropic" {
            $values["ANTHROPIC_API_KEY"] = $SelectedApiKey
        }
        default {
            $values["OPENAI_API_KEY"] = $SelectedApiKey
            $values["OPENAI_BASE_URL"] = $SelectedBaseUrl
        }
    }

    return $values
}

function Get-OpenClawEnvValues {
    param(
        [Parameter(Mandatory)][string]$SelectedProvider,
        [Parameter(Mandatory)][string]$SelectedApiKey,
        [Parameter(Mandatory)][string]$SelectedBaseUrl
    )

    $values = @{
        "OPENROUTER_API_KEY" = ""
        "OPENAI_API_KEY"     = ""
        "OPENAI_BASE_URL"    = ""
        "ANTHROPIC_API_KEY"  = ""
    }

    switch ($SelectedProvider) {
        "openrouter" {
            $values["OPENROUTER_API_KEY"] = $SelectedApiKey
        }
        "openai" {
            $values["OPENAI_API_KEY"] = $SelectedApiKey
        }
        "anthropic" {
            $values["ANTHROPIC_API_KEY"] = $SelectedApiKey
        }
        default {
            $values["OPENAI_API_KEY"] = $SelectedApiKey
            $values["OPENAI_BASE_URL"] = $SelectedBaseUrl
        }
    }

    return $values
}

function Get-OpenClawModelRef {
    param(
        [Parameter(Mandatory)][string]$SelectedProvider,
        [Parameter(Mandatory)][string]$SelectedModel
    )

    $prefix = switch ($SelectedProvider) {
        "openrouter" { "openrouter/" }
        "openai"     { "openai/" }
        "anthropic"  { "anthropic/" }
        default      { "openai/" }
    }

    if ($SelectedModel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $SelectedModel
    }

    return $prefix + $SelectedModel
}

function Configure-HermesSettings {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$HomeUnc
    )

    $envValues = Get-HermesEnvValues -SelectedProvider $Provider -SelectedApiKey $ApiKey -SelectedBaseUrl $BaseUrl
    $envKeys = @("OPENROUTER_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "ANTHROPIC_API_KEY")

    if (Test-WslCommandExists -Distro $Distro -CommandName "hermes") {
        $commands = @(
            "set -euo pipefail",
            "hermes config set model.default $(ConvertTo-BashSingleQuoted $Model)",
            "hermes config set model.provider $(ConvertTo-BashSingleQuoted $Provider)",
            "hermes config set model.base_url $(ConvertTo-BashSingleQuoted $BaseUrl)"
        )

        foreach ($key in $envKeys) {
            $commands += "hermes config set $key $(ConvertTo-BashSingleQuoted $envValues[$key])"
        }

        Invoke-WslCommand -Distro $Distro -Command ($commands -join "`n")
    } else {
        $configDir = Join-Path $HomeUnc ".hermes"
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null

        @"
model:
  default: $(ConvertTo-YamlSingleQuoted $Model)
  provider: $(ConvertTo-YamlSingleQuoted $Provider)
  base_url: $(ConvertTo-YamlSingleQuoted $BaseUrl)
"@ | Set-Content -LiteralPath (Join-Path $configDir "config.yaml") -Encoding UTF8

        Set-DotEnvValues -Path (Join-Path $configDir ".env") -Values $envValues -KeyOrder $envKeys
    }

    Write-Ok "Hermes config written to $(Join-Path $HomeUnc '.hermes')"
}

function Configure-OpenClawSettings {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$HomeUnc
    )

    $configDir = Join-Path $HomeUnc ".openclaw"
    $configPath = Join-Path $configDir "openclaw.json"
    $envPath = Join-Path $configDir ".env"
    $envKeys = @("OPENROUTER_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "ANTHROPIC_API_KEY")
    $envValues = Get-OpenClawEnvValues -SelectedProvider $Provider -SelectedApiKey $ApiKey -SelectedBaseUrl $BaseUrl
    $modelRef = Get-OpenClawModelRef -SelectedProvider $Provider -SelectedModel $Model

    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Set-DotEnvValues -Path $envPath -Values $envValues -KeyOrder $envKeys

    if (Test-WslCommandExists -Distro $Distro -CommandName "openclaw") {
        $commands = @(
            "set -euo pipefail",
            "openclaw config set agents.defaults.model.primary $(ConvertTo-BashSingleQuoted $modelRef)"
        )
        Invoke-WslCommand -Distro $Distro -Command ($commands -join "`n")
    } else {
        $configObject = $null
        if (Test-Path -LiteralPath $configPath) {
            try {
                $configObject = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            } catch {
                $configObject = $null
            }
        }

        if (-not $configObject) {
            $configObject = [pscustomobject]@{}
        }
        if (-not $configObject.PSObject.Properties["agents"]) {
            $configObject | Add-Member -NotePropertyName "agents" -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $configObject.agents.PSObject.Properties["defaults"]) {
            $configObject.agents | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $configObject.agents.defaults.PSObject.Properties["model"]) {
            $configObject.agents.defaults | Add-Member -NotePropertyName "model" -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $configObject.agents.defaults.model.PSObject.Properties["primary"]) {
            $configObject.agents.defaults.model | Add-Member -NotePropertyName "primary" -NotePropertyValue $modelRef
        } else {
            $configObject.agents.defaults.model.primary = $modelRef
        }

        $configObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8
    }

    Write-Ok "OpenClaw config written to $(Join-Path $HomeUnc '.openclaw')"
}

if ($SharedDir -and (Test-Path "$SharedDir\verify-llm.py") -and (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Step "Verifying API connection..."
    $result = & python "$SharedDir\verify-llm.py" --provider $Provider --api-key $ApiKey --base-url $BaseUrl --model $Model 2>&1
    Write-Host $result
} else {
    Write-Warn "Skipping API verification on Windows because Python is not available."
}

$distro = Assert-Wsl2Ready
$homeUnc = Get-WslHomeUncPath -Distro $distro.Name

if ($Hermes) {
    Configure-HermesSettings -Distro $distro.Name -HomeUnc $homeUnc
}

if ($OpenClaw) {
    Configure-OpenClawSettings -Distro $distro.Name -HomeUnc $homeUnc
}
