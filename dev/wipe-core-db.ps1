param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$DbPath = "data\\recorder-core.db"
)

Set-Location $RepoRoot

Write-Host "[wipe-core-db] repo: $RepoRoot"
Write-Host "[wipe-core-db] db: $DbPath"

# Best-effort: stop a running recorder_core (if Core is running on Windows).
Get-Process recorder_core -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item -Force -ErrorAction SilentlyContinue $DbPath
Remove-Item -Force -ErrorAction SilentlyContinue "$DbPath-wal"
Remove-Item -Force -ErrorAction SilentlyContinue "$DbPath-shm"
Remove-Item -Force -ErrorAction SilentlyContinue "$DbPath-journal"

Write-Host "[wipe-core-db] done."
Write-Host "[wipe-core-db] next: cargo run -p recorder_core -- --listen 127.0.0.1:17600"

