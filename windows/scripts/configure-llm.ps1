# configure-llm.ps1 — Write LLM config for selected products
# Called by Inno Setup with parameters from custom wizard pages.

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

# Provider defaults
$defaults = @{
    "openrouter" = @{ base_url = "https://openrouter.ai/api/v1"; model = "nousresearch/hermes-3-llama-3.1-8b" }
    "openai"     = @{ base_url = "https://api.openai.com/v1"; model = "gpt-4o-mini" }
    "anthropic"  = @{ base_url = "https://api.anthropic.com"; model = "claude-sonnet-4-20250514" }
}

if (-not $BaseUrl -and $defaults.ContainsKey($Provider)) { $BaseUrl = $defaults[$Provider].base_url }
if (-not $Model -and $defaults.ContainsKey($Provider)) { $Model = $defaults[$Provider].model }

# Verify connectivity
if ($SharedDir -and (Test-Path "$SharedDir\verify-llm.py")) {
    Write-Host "[*] Verifying API connection..." -ForegroundColor Cyan
    $result = & python "$SharedDir\verify-llm.py" --provider $Provider --api-key $ApiKey --base-url $BaseUrl --model $Model 2>&1
    Write-Host $result
}

# Write Hermes config
if ($Hermes) {
    $configDir = "$env:USERPROFILE\.hermes"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    @"
provider: $Provider
model: $Model
api_key: $ApiKey
base_url: $BaseUrl
"@ | Set-Content "$configDir\config.yaml" -Encoding UTF8
    Write-Host "[OK] Hermes config written" -ForegroundColor Green
}

# Write OpenClaw config
if ($OpenClaw) {
    $configDir = "$env:USERPROFILE\.openclaw"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $provPrefix = switch ($Provider) {
        "openrouter" { "openrouter" }
        "openai"     { "openai" }
        "anthropic"  { "anthropic" }
        default      { "openai" }
    }
    @"
{
  "agent": {
    "model": "$provPrefix/$Model"
  },
  "providers": {
    "$provPrefix": {
      "apiKey": "$ApiKey"
    }
  }
}
"@ | Set-Content "$configDir\openclaw.json" -Encoding UTF8
    Write-Host "[OK] OpenClaw config written" -ForegroundColor Green
}
