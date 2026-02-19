param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$CoreUrl = "http://127.0.0.1:17600",
  [string]$DbPath = "data\\recorder-core.db",
  [switch]$Restart,
  [switch]$NoBuild,
  [switch]$SendTitle,
  # NOTE: when invoked via `powershell.exe -File ...`, values like `$true` are passed as strings.
  # Keep these as strings and parse manually for best compatibility with UI/Process-run callers.
  [string]$TrackAudio = "true",
  [string]$ReviewNotify = "true"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-agent] repo: $RepoRoot"
Write-Host "[run-agent] core: $CoreUrl"

function Parse-BoolStrict {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][object]$Value
  )

  if ($null -eq $Value) { return $false }

  if ($Value -is [bool]) { return [bool]$Value }
  if ($Value -is [int]) { return ([int]$Value -ne 0) }

  $s = $Value.ToString().Trim()
  if ($s.Length -eq 0) { return $false }

  $lower = $s.ToLowerInvariant()
  if ($lower -eq "1") { return $true }
  if ($lower -eq "0") { return $false }
  if ($lower -eq "true" -or $lower -eq "`$true") { return $true }
  if ($lower -eq "false" -or $lower -eq "`$false") { return $false }
  if ($lower -eq "yes" -or $lower -eq "y" -or $lower -eq "on") { return $true }
  if ($lower -eq "no" -or $lower -eq "n" -or $lower -eq "off") { return $false }

  throw "Invalid -${Name}: '$s' (use true/false or 1/0)"
}

try {
  $coreUri = [Uri]$CoreUrl
} catch {
  throw "Invalid -CoreUrl: $CoreUrl"
}

$port = $coreUri.Port
if ($port -le 0) { $port = 17600 }

$listen = "$($coreUri.Host):$port"

if ($Restart) {
  Write-Host "[run-agent] stopping existing processes..."
  Get-Process windows_collector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-Process recorder_core -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if (-not $NoBuild) {
  Write-Host "[run-agent] cargo build -p recorder_core --release"
  cargo build -p recorder_core --release
  Write-Host "[run-agent] cargo build -p windows_collector --release"
  cargo build -p windows_collector --release
}

$coreExe = Join-Path $RepoRoot "target\\release\\recorder_core.exe"
$collectorExe = Join-Path $RepoRoot "target\\release\\windows_collector.exe"

if (-not (Test-Path $coreExe)) {
  throw "recorder_core.exe not found at: $coreExe"
}
if (-not (Test-Path $collectorExe)) {
  throw "windows_collector.exe not found at: $collectorExe"
}

$logDir = Join-Path $RepoRoot "data\\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$coreOutLog = Join-Path $logDir "core.log"
$coreErrLog = Join-Path $logDir "core.err.log"
$collectorOutLog = Join-Path $logDir "collector.log"
$collectorErrLog = Join-Path $logDir "collector.err.log"

function Test-CoreHealth {
  try {
    $j = Invoke-RestMethod -TimeoutSec 1 "$CoreUrl/health"
    if ($j -and $j.ok -eq $true) { return $true }
    return $false
  } catch {
    return $false
  }
}

$coreStarted = $false
$coreProc = $null

if (Test-CoreHealth) {
  Write-Host "[run-agent] core already healthy; skip starting"
} else {
  Write-Host "[run-agent] starting core (listen=$listen, db=$DbPath)"
  $coreProc = Start-Process `
    -FilePath $coreExe `
    -ArgumentList @("--listen", $listen, "--db", $DbPath) `
    -WorkingDirectory $RepoRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $coreOutLog `
    -RedirectStandardError $coreErrLog
  $coreStarted = $true

  $ok = $false
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-CoreHealth) { $ok = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ok) {
    throw "Core did not become healthy at $CoreUrl. Check $coreOutLog and $coreErrLog"
  }
}

# Always ensure a single collector instance (avoid duplicated events).
Get-Process windows_collector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$trackAudioBool = Parse-BoolStrict -Name "TrackAudio" -Value $TrackAudio
$reviewNotifyBool = Parse-BoolStrict -Name "ReviewNotify" -Value $ReviewNotify

$trackAudioArg = $trackAudioBool.ToString().ToLowerInvariant()
$reviewNotifyArg = $reviewNotifyBool.ToString().ToLowerInvariant()

$collectorArgs = @(
  "--core-url", $CoreUrl,
  "--track-audio=$trackAudioArg",
  "--review-notify=$reviewNotifyArg"
)
if ($SendTitle) { $collectorArgs += "--send-title" }

Write-Host "[run-agent] starting collector (track_audio=$trackAudioArg, review_notify=$reviewNotifyArg)"
$collectorProc = Start-Process `
  -FilePath $collectorExe `
  -ArgumentList $collectorArgs `
  -WorkingDirectory $RepoRoot `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $collectorOutLog `
  -RedirectStandardError $collectorErrLog

$pidInfo = @{
  coreUrl = $CoreUrl
  listen = $listen
  dbPath = $DbPath
  startedAt = (Get-Date).ToString("o")
  corePid = if ($coreStarted -and $coreProc) { $coreProc.Id } else { $null }
  collectorPid = if ($collectorProc) { $collectorProc.Id } else { $null }
  coreLog = $coreOutLog
  collectorLog = $collectorOutLog
  coreStdoutLog = $coreOutLog
  coreStderrLog = $coreErrLog
  collectorStdoutLog = $collectorOutLog
  collectorStderrLog = $collectorErrLog
}

$pidFile = Join-Path $RepoRoot "data\\agent-pids.json"
$pidInfo | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 $pidFile

Write-Host "[run-agent] ok"
Write-Host "[run-agent] pids: $pidFile"
Write-Host "[run-agent] logs:"
Write-Host "  core: $coreOutLog"
Write-Host "  core(err): $coreErrLog"
Write-Host "  collector: $collectorOutLog"
Write-Host "  collector(err): $collectorErrLog"
