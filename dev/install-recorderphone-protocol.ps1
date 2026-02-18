param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$ExePath = ""
)

Set-Location $RepoRoot

$protocol = "recorderphone"
$keyPath = "HKCU:\\Software\\Classes\\$protocol"

function Resolve-DefaultExePath {
  $candidates = @(
    (Join-Path $RepoRoot "recorderphone_ui\\build\\windows\\x64\\runner\\Debug\\recorderphone_ui.exe"),
    (Join-Path $RepoRoot "recorderphone_ui\\build\\windows\\x64\\runner\\Release\\recorderphone_ui.exe")
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return (Resolve-Path $p).Path }
  }
  return ""
}

if ([string]::IsNullOrWhiteSpace($ExePath)) {
  $ExePath = Resolve-DefaultExePath
} else {
  $ExePath = (Resolve-Path $ExePath).Path
}

if ([string]::IsNullOrWhiteSpace($ExePath) -or -not (Test-Path $ExePath)) {
  Write-Host "[protocol] recorderphone_ui.exe not found."
  Write-Host "  Expected one of:"
  Write-Host "    $RepoRoot\\recorderphone_ui\\build\\windows\\x64\\runner\\Debug\\recorderphone_ui.exe"
  Write-Host "    $RepoRoot\\recorderphone_ui\\build\\windows\\x64\\runner\\Release\\recorderphone_ui.exe"
  Write-Host ""
  Write-Host "Fix:"
  Write-Host "  1) Build/run the Flutter Windows app once:"
  Write-Host "       cd $RepoRoot\\recorderphone_ui"
  Write-Host "       flutter run -d windows"
  Write-Host "  2) Re-run this script, or pass -ExePath explicitly."
  exit 2
}

Write-Host "[protocol] Installing $protocol:// handler -> $ExePath"

New-Item -Path $keyPath -Force | Out-Null
New-ItemProperty -Path $keyPath -Name "(default)" -Value "URL:RecorderPhone Protocol" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $keyPath -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null

$cmdKey = Join-Path $keyPath "shell\\open\\command"
New-Item -Path $cmdKey -Force | Out-Null

# Command must be: "<exePath>" "%1"
$command = "`"$ExePath`" `"%1`""
New-ItemProperty -Path $cmdKey -Name "(default)" -Value $command -PropertyType String -Force | Out-Null

Write-Host "[protocol] Done."
Write-Host "Test:"
Write-Host "  Win+R -> $protocol://review"
