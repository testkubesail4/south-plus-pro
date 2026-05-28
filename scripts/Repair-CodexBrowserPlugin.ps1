param(
  [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$pluginRoot = Join-Path $CodexHome "plugins\cache\openai-bundled"
$browserRoot = Join-Path $pluginRoot "browser"
$chromeRoot = Join-Path $pluginRoot "chrome"

if (-not (Test-Path -LiteralPath $browserRoot)) {
  throw "Browser plugin cache not found: $browserRoot"
}
if (-not (Test-Path -LiteralPath $chromeRoot)) {
  throw "Chrome plugin cache not found: $chromeRoot"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $browserVersion = Get-ChildItem -LiteralPath $browserRoot -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $browserVersion) {
    throw "No Browser plugin version found under $browserRoot"
  }
  $Version = $browserVersion.Name
}

$browserNodeModules = Join-Path $browserRoot "$Version\scripts\node_modules"
$chromeNodeModules = Join-Path $chromeRoot "$Version\scripts\node_modules"

if (-not (Test-Path -LiteralPath $browserNodeModules)) {
  throw "Browser node_modules not found: $browserNodeModules"
}
if (-not (Test-Path -LiteralPath $chromeNodeModules)) {
  throw "Matching Chrome node_modules not found: $chromeNodeModules"
}

function Restore-Package {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$RequiredFile
  )

  $source = Join-Path $chromeNodeModules $Name
  $target = Join-Path $browserNodeModules $Name
  $requiredTarget = Join-Path $target $RequiredFile

  if (-not (Test-Path -LiteralPath $source)) {
    throw "Source package not found in Chrome plugin cache: $source"
  }

  if (Test-Path -LiteralPath $requiredTarget) {
    Write-Host "OK: $Name already has $RequiredFile"
    return
  }

  if (Test-Path -LiteralPath $target) {
    $backup = "$target.bak-$(Get-Date -Format yyyyMMddHHmmss)"
    Rename-Item -LiteralPath $target -NewName (Split-Path -Leaf $backup)
    Write-Host "Backed up incomplete package: $backup"
  }

  Copy-Item -LiteralPath $source -Destination $target -Recurse
  Write-Host "Restored: $Name"
}

Restore-Package -Name "classic-level" -RequiredFile "index.js"
Restore-Package -Name "abstract-level" -RequiredFile "index.js"

Write-Host "Browser plugin repair complete for version $Version."
