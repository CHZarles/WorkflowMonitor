param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [switch]$KillAllByName
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[stop-agent] repo: $RepoRoot"

$pidFile = Join-Path $RepoRoot "data\\agent-pids.json"
if (Test-Path $pidFile) {
  try {
    $raw = Get-Content -Raw $pidFile
    $info = $raw | ConvertFrom-Json
    $corePid = $info.corePid
    $collectorPid = $info.collectorPid

    if ($collectorPid) {
      Write-Host "[stop-agent] stopping collector pid=$collectorPid"
      Stop-Process -Id $collectorPid -Force -ErrorAction SilentlyContinue
    }
    if ($corePid) {
      Write-Host "[stop-agent] stopping core pid=$corePid"
      Stop-Process -Id $corePid -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host "[stop-agent] failed to read pid file: $pidFile"
  }
} else {
  Write-Host "[stop-agent] pid file not found: $pidFile"
}

if ($KillAllByName) {
  Write-Host "[stop-agent] KillAllByName: stopping all windows_collector + recorder_core processes"
  Get-Process windows_collector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-Process recorder_core -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "[stop-agent] done"

