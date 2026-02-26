param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  # Flutter's `-d` expects an actual device id (e.g. `emulator-5554`, `R58N...`, `sdk gphone64 x86 64`),
  # not a platform name. Leave empty to let `flutter run` select / prompt.
  [string]$Device = ""
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

# Best-effort: stop stale Gradle daemons to avoid buildLogic.lock timeouts.
try {
  Push-Location ".\\android"
  if (Test-Path ".\\gradlew.bat") {
    Write-Host "[run-android] gradle --stop (best-effort)"
    .\\gradlew.bat --stop | Out-Host
  }
} catch {
  # ignore
} finally {
  try { Pop-Location } catch {}
}

# Best-effort: clean stale lock file (it will fail if another Gradle still holds it).
try {
  $lock = ".\\android\\.gradle\\noVersion\\buildLogic.lock"
  if (Test-Path $lock) {
    Remove-Item -Force $lock -ErrorAction SilentlyContinue
  }
} catch {
  # ignore
}

Write-Host "[run-android] flutter devices"
$devices = $null
try {
  $devices = flutter devices --machine | ConvertFrom-Json
} catch {
  # Fallback to human-readable output.
  flutter devices | Out-Host
}

$androidCount = 0
if ($devices -ne $null) {
  $androidCount = @($devices | Where-Object { $_.targetPlatform -like "android*" }).Count
}

if ($devices -ne $null -and $androidCount -eq 0) {
  Write-Host ""
  Write-Host "[run-android] No Android devices/emulators detected."
  Write-Host "  - For a phone: enable USB debugging, connect via USB, then run: adb devices"
  Write-Host "  - For an emulator: start one in Android Studio -> Device Manager"
  Write-Host "  - Check toolchain: flutter doctor -v"
  Write-Host ""

  if ([string]::IsNullOrWhiteSpace($Device)) {
    throw "No Android device found. Connect a phone/emulator, then re-run. (Tip: `flutter devices`)"
  }
}

if ([string]::IsNullOrWhiteSpace($Device)) {
  Write-Host "[run-android] flutter run (will prompt if multiple devices are connected)"
  flutter run
} else {
  Write-Host "[run-android] flutter run -d $Device"
  flutter run -d $Device
}

Pop-Location
