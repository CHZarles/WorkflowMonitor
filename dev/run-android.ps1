param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$Device = "android"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-android] repo: $RepoRoot"

powershell -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "dev\\overlay-ui.ps1") -RepoRoot $RepoRoot

Push-Location (Join-Path $RepoRoot "recorderphone_ui")

if (-not (Test-Path ".\\android\\app")) {
  Write-Host "[run-android] missing android/ platform files -> flutter create --platforms=windows,android --overwrite ."
  flutter create --platforms=windows,android --overwrite .
}

Write-Host "[run-android] flutter run -d $Device"
flutter run -d $Device

Pop-Location

