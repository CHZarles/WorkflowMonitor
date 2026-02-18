param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

Set-Location $RepoRoot

Write-Host "[overlay-ui] repo: $RepoRoot"

if (-not (Test-Path ".\\ui_flutter\\template\\lib")) {
  throw "Missing ui_flutter\\template\\lib. Run from the RecorderPhone repo."
}

if (-not (Test-Path ".\\recorderphone_ui")) {
  throw "Missing recorderphone_ui. Create the Flutter project on Windows first."
}

Write-Host "[overlay-ui] robocopy template\\lib -> recorderphone_ui\\lib"
robocopy ".\\ui_flutter\\template\\lib" ".\\recorderphone_ui\\lib" /MIR | Out-Host

Write-Host "[overlay-ui] copy template\\pubspec.yaml -> recorderphone_ui\\pubspec.yaml"
Copy-Item -Force ".\\ui_flutter\\template\\pubspec.yaml" ".\\recorderphone_ui\\pubspec.yaml"

Push-Location ".\\recorderphone_ui"
Write-Host "[overlay-ui] flutter pub get"
flutter pub get
Pop-Location

Write-Host "[overlay-ui] done. Next:"
Write-Host "  cd .\\recorderphone_ui"
Write-Host "  flutter run -d windows"
