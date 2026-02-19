param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$Listen = "127.0.0.1:17600",
  [string]$DbPath = "data\\recorder-core.db"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-core] repo: $RepoRoot"
Write-Host "[run-core] listen: $Listen"
Write-Host "[run-core] db: $DbPath"

if (-not (Test-Path ".\\data")) {
  New-Item -ItemType Directory -Force ".\\data" | Out-Null
}

Write-Host "[run-core] cargo build -p recorder_core --release"
cargo build -p recorder_core --release

$exe = Join-Path $RepoRoot "target\\release\\recorder_core.exe"
if (-not (Test-Path $exe)) {
  throw "recorder_core.exe not found at: $exe"
}

Write-Host "[run-core] $exe --listen $Listen --db $DbPath"
& $exe --listen $Listen --db $DbPath

