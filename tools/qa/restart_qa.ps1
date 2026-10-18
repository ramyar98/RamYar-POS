# Restarts the RAMYAR POS QA session: the desktop server and the phone client,
# both with the QA harness compiled in, and with fresh log files.
param(
  [switch]$SkipWindows,
  [switch]$SkipAndroid
)
$ErrorActionPreference = "Continue"
$base = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode"
$project = "D:\project biablu\Biablu"

Get-Process ramyar_pos -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process dart -ErrorAction SilentlyContinue |
  Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-60) } |
  Stop-Process -Force -ErrorAction SilentlyContinue
adb shell am force-stop com.kalakchi.ramyar.pos 2>$null | Out-Null
Start-Sleep -Seconds 3

if (-not $SkipWindows) {
  Set-Location $project
  $env:RAMYAR_BUILD_TYPE = "Debug"
  Remove-Item "$base\win_run.log" -Force -ErrorAction SilentlyContinue
  Remove-Item "$base\win_run.err" -Force -ErrorAction SilentlyContinue
  Start-Process -FilePath "flutter" `
    -ArgumentList "run", "-d", "windows", "--dart-define=RAMYAR_QA=true" `
    -RedirectStandardOutput "$base\win_run.log" `
    -RedirectStandardError "$base\win_run.err" -NoNewWindow
  Write-Output "windows: launching"
}

if (-not $SkipAndroid) {
  Set-Location $project
  Remove-Item "$base\and_run.log" -Force -ErrorAction SilentlyContinue
  Remove-Item "$base\and_run.err" -Force -ErrorAction SilentlyContinue
  Start-Process -FilePath "flutter" `
    -ArgumentList "run", "-d", "RZ8R317METV", "--dart-define=RAMYAR_QA=true" `
    -RedirectStandardOutput "$base\and_run.log" `
    -RedirectStandardError "$base\and_run.err" -NoNewWindow
  Write-Output "android: launching"
}
Write-Output "waiting for both to reach a logged-in home screen..."
