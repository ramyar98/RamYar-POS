# QA log helper for RAMYAR POS.
#   qa_log.ps1 win <n>        - last n QA lines from the Windows run
#   qa_log.ps1 winerr <n>     - last n QA-ERROR lines from the Windows run
#   qa_log.ps1 and <n>        - last n QA lines from the Android run (via the
#                               android log file, not logcat, so it is replayable)
#   qa_log.ps1 screen <file>  - the most recent [QA-SCREEN] line, decoded
param([string]$Target = "win", [int]$Count = 20, [string]$Path = "", [string]$OutFile = "")
$ErrorActionPreference = "Continue"
# Kurdish/Arabic labels are the whole point of the digest, so the console has to
# be UTF-8 or every label arrives as '?'.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$base = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode"
if ($Path -eq "") {
  $Path = switch ($Target) {
    "win"     { "$base\win_run.log" }
    "winerr"  { "$base\win_run.log" }
    "and"     { "$base\and_run.log" }
    "anderr"  { "$base\and_run.log" }
    default   { "$base\win_run.log" }
  }
}
$lines = Get-Content -LiteralPath $Path -Encoding UTF8
if ($Target -eq "winerr" -or $Target -eq "anderr") {
  $lines = $lines | Where-Object { $_ -match "\[QA-ERROR\]" }
} elseif ($Target -eq "screen") {
  $lines = $lines | Where-Object { $_ -match "\[QA-SCREEN\]" }
} elseif ($Target -eq "raw") {
  # nothing
} else {
  $lines = $lines | Where-Object { $_ -match "\[QA-" }
}
$lines = $lines | Select-Object -Last $Count
if ($OutFile -ne "") {
  [System.IO.File]::WriteAllLines($OutFile, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "wrote $($lines.Count) lines to $OutFile"
} else {
  $lines
}
