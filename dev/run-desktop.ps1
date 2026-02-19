param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$CoreUrl = "http://127.0.0.1:17600",
  [string]$Device = "windows",
  [switch]$RestartAgent,
  [switch]$NoBuild,
  [switch]$SendTitle,
  [string]$TrackAudio = "true",
  [string]$ReviewNotify = "true"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-desktop] repo: $RepoRoot"
Write-Host "[run-desktop] core: $CoreUrl"

& (Join-Path $RepoRoot "dev\\run-agent.ps1") `
  -RepoRoot $RepoRoot `
  -CoreUrl $CoreUrl `
  -Restart:$RestartAgent `
  -NoBuild:$NoBuild `
  -SendTitle:$SendTitle `
  -TrackAudio $TrackAudio `
  -ReviewNotify $ReviewNotify

& (Join-Path $RepoRoot "dev\\run-ui.ps1") `
  -RepoRoot $RepoRoot `
  -Device $Device
