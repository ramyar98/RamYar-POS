# Cashier (Windows) side: read the current screen.
param(
  [int]$Count = 2,
  [string]$Match = "\[QA-SCREEN\]",
  [switch]$Errors
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# QA scratch folder for the log files. Same default as before (%TEMP%\opencode)
# but derived from the environment, so it works for any Windows user; override
# with the RAMYAR_QA_BASE environment variable.
$base = if ($env:RAMYAR_QA_BASE) { $env:RAMYAR_QA_BASE } else { Join-Path $env:TEMP "opencode" }
Copy-Item "$base\win_run.log" "$base\win_copy.log" -Force -ErrorAction SilentlyContinue
if ($Errors) { $Match = "\[QA-ERROR\]" }
Select-String -Path "$base\win_copy.log" -Pattern $Match -Encoding UTF8 |
  Select-Object -Last $Count | ForEach-Object { $_.Line }
