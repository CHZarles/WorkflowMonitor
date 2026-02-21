param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$OutDir = "",
  [switch]$NoBuild,
  [switch]$NoOverlayUI,
  [switch]$InstallProtocol,
  [switch]$Zip
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[package] repo: $RepoRoot"

function Invoke-Robocopy {
  param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To
  )

  robocopy $From $To /MIR | Out-Host
  $code = $LASTEXITCODE
  # robocopy exit codes: < 8 are success (0..7). >= 8 indicates failure.
  if ($code -ge 8) {
    throw "robocopy failed with exit code $code"
  }
}

if (-not $NoOverlayUI) {
  Write-Host "[package] overlay UI template -> recorderphone_ui"
  & (Join-Path $RepoRoot "dev\\overlay-ui.ps1") -RepoRoot $RepoRoot
}

if (-not $NoBuild) {
  Write-Host "[package] cargo build -p recorder_core --release"
  cargo build -p recorder_core --release
  Write-Host "[package] cargo build -p windows_collector --release"
  cargo build -p windows_collector --release
} else {
  Write-Host "[package] -NoBuild: skip cargo build"
}

$coreExe = Join-Path $RepoRoot "target\\release\\recorder_core.exe"
$collectorExe = Join-Path $RepoRoot "target\\release\\windows_collector.exe"

if (-not (Test-Path $coreExe)) {
  throw "recorder_core.exe not found at: $coreExe"
}
if (-not (Test-Path $collectorExe)) {
  throw "windows_collector.exe not found at: $collectorExe"
}

if (-not (Test-Path (Join-Path $RepoRoot "recorderphone_ui\\pubspec.yaml"))) {
  throw "Missing recorderphone_ui (Flutter project). Run: flutter create --platforms=windows,android recorderphone_ui"
}

if (-not $NoBuild) {
  Push-Location (Join-Path $RepoRoot "recorderphone_ui")
  Write-Host "[package] flutter build windows --release"
  flutter build windows --release
  Pop-Location
} else {
  Write-Host "[package] -NoBuild: skip flutter build"
}

$flutterReleaseDir = Join-Path $RepoRoot "recorderphone_ui\\build\\windows\\x64\\runner\\Release"
if (-not (Test-Path $flutterReleaseDir)) {
  throw "Flutter release output not found at: $flutterReleaseDir"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path $RepoRoot "dist\\windows\\RecorderPhone"
}

Write-Host "[package] staging -> $OutDir"

function Stop-ProcessByExecutablePath {
  param([Parameter(Mandatory = $true)][string]$ExePath)
  if (-not (Test-Path $ExePath)) { return }
  $full = ""
  try {
    $full = (Resolve-Path $ExePath).Path
  } catch {
    return
  }
  $name = Split-Path $full -Leaf
  try {
    $procs = Get-CimInstance Win32_Process -Filter "Name='$name'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
      $ep = $p.ExecutablePath
      if ($ep -and ($ep -ieq $full)) {
        Write-Host "[package] stopping $name pid=$($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {
    # best effort
  }
}

# If previous packaged binaries are still running, stop them so we can overwrite/delete.
Stop-ProcessByExecutablePath (Join-Path $OutDir "RecorderPhone.exe")
Stop-ProcessByExecutablePath (Join-Path $OutDir "recorderphone_ui.exe")
Stop-ProcessByExecutablePath (Join-Path $OutDir "recorder_core.exe")
Stop-ProcessByExecutablePath (Join-Path $OutDir "windows_collector.exe")
Start-Sleep -Milliseconds 200

New-Item -ItemType Directory -Force $OutDir | Out-Null
Invoke-Robocopy -From $flutterReleaseDir -To $OutDir

# Bundle agent binaries next to the UI exe so the app can start them in "packaged mode".
Copy-Item -Force $coreExe (Join-Path $OutDir "recorder_core.exe")
Copy-Item -Force $collectorExe (Join-Path $OutDir "windows_collector.exe")

# Resolve UI entrypoint exe.
$uiExe = Join-Path $OutDir "recorderphone_ui.exe"
$distExe = Join-Path $OutDir "RecorderPhone.exe"

if ((Test-Path $uiExe) -and (-not (Test-Path $distExe))) {
  Move-Item -Force $uiExe $distExe
}

if (-not (Test-Path $distExe) -and -not (Test-Path $uiExe)) {
  $other = Get-ChildItem -Path $OutDir -Filter "*.exe" -File -ErrorAction SilentlyContinue `
    | Where-Object { $_.Name -ne "recorder_core.exe" -and $_.Name -ne "windows_collector.exe" } `
    | Select-Object -First 1
  if ($other) {
    $distExe = $other.FullName
  } else {
    throw "UI exe not found in: $OutDir (check Flutter build output at: $flutterReleaseDir)"
  }
}

if ($InstallProtocol) {
  if (-not (Test-Path $distExe)) {
    # Fallback if exe wasn't renamed.
    $distExe = $uiExe
  }
  Write-Host "[package] installing recorderphone:// protocol -> $distExe"
  & (Join-Path $RepoRoot "dev\\install-recorderphone-protocol.ps1") -RepoRoot $RepoRoot -ExePath $distExe
}

if ($Zip) {
  $zipPath = Join-Path (Split-Path $OutDir -Parent) "RecorderPhone-windows.zip"
  if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
  Write-Host "[package] zip -> $zipPath"
  Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath -Force
}

Write-Host "[package] done."
Write-Host "Next:"
if (Test-Path $distExe) {
  Write-Host "  Start: $distExe"
} else {
  Write-Host "  Start: $uiExe"
}
