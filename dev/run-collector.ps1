param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$CoreUrl = "http://127.0.0.1:17600",
  [switch]$SendTitle,
  [string]$TrackAudio = "true",
  [string]$ReviewNotify = "true"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoRoot

Write-Host "[run-collector] repo: $RepoRoot"
Write-Host "[run-collector] core: $CoreUrl"

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

Write-Host "[run-collector] cargo build -p windows_collector --release"
cargo build -p windows_collector --release

$exe = Join-Path $RepoRoot "target\\release\\windows_collector.exe"
if (-not (Test-Path $exe)) {
  throw "windows_collector.exe not found at: $exe"
}

$trackAudioBool = Parse-BoolStrict -Name "TrackAudio" -Value $TrackAudio
$reviewNotifyBool = Parse-BoolStrict -Name "ReviewNotify" -Value $ReviewNotify

$trackAudioArg = $trackAudioBool.ToString().ToLowerInvariant()
$reviewNotifyArg = $reviewNotifyBool.ToString().ToLowerInvariant()

$args = @("--core-url", $CoreUrl, "--track-audio=$trackAudioArg", "--review-notify=$reviewNotifyArg")
if ($SendTitle) {
  $args += "--send-title"
}

Write-Host "[run-collector] $exe $($args -join ' ')"
& $exe @args
