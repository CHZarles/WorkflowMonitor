param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$CoreUrl = "http://127.0.0.1:17600",
  [switch]$SendTitle,
  [bool]$TrackAudio = $true,
  [bool]$ReviewNotify = $true
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-collector] repo: $RepoRoot"
Write-Host "[run-collector] core: $CoreUrl"

Write-Host "[run-collector] cargo build -p windows_collector --release"
cargo build -p windows_collector --release

$exe = Join-Path $RepoRoot "target\\release\\windows_collector.exe"
if (-not (Test-Path $exe)) {
  throw "windows_collector.exe not found at: $exe"
}

$args = @("--core-url", $CoreUrl, "--track-audio=$TrackAudio", "--review-notify=$ReviewNotify")
if ($SendTitle) {
  $args += "--send-title"
}

Write-Host "[run-collector] $exe $($args -join ' ')"
& $exe @args

