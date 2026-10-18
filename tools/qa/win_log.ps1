# Cashier (Windows) side: read the current screen.
param(
  [int]$Count = 2,
  [string]$Match = "\[QA-SCREEN\]",
  [switch]$Errors
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$base = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode"
Copy-Item "$base\win_run.log" "$base\win_copy.log" -Force -ErrorAction SilentlyContinue
if ($Errors) { $Match = "\[QA-ERROR\]" }
Select-String -Path "$base\win_copy.log" -Pattern $Match -Encoding UTF8 |
  Select-Object -Last $Count | ForEach-Object { $_.Line }
