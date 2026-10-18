# Android UI driver for RAMYAR POS QA.
#
#   android_ui.ps1 view            - window geometry (view size, ratio, display offset)
#   android_ui.ps1 screen [n]      - last n screen digests, decoded UTF-8
#   android_ui.ps1 tap <x> <y>     - tap at LOGICAL view coordinates
#   android_ui.ps1 taptext <text>  - tap the centre of a label from the latest digest
#   android_ui.ps1 swipe <x1> <y1> <x2> <y2> [ms]
#   android_ui.ps1 back
#   android_ui.ps1 err [n]         - framework errors the app captured
param(
  [string]$Cmd = "view",
  [double]$X = 0, [double]$Y = 0,
  [string]$Text = "",
  [double]$X1 = 0, [double]$Y1 = 0, [double]$X2 = 0, [double]$Y2 = 0,
  [int]$Ms = 300,
  [int]$Count = 1
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$base = if ($env:RAMYAR_QA_BASE) { $env:RAMYAR_QA_BASE } else { Join-Path $env:TEMP "opencode" }
$log = "$base\and_run.log"

function Get-Digest {
  if (-not (Test-Path $log)) { return $null }
  Copy-Item $log "$base\and_copy.log" -Force -ErrorAction SilentlyContinue
  $m = Select-String -Path "$base\and_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
       Select-Object -Last 1
  if ($m -eq $null) { return $null }
  return $m.Line
}

function Get-ViewInfo {
  $line = $null
  if (Test-Path $log) {
    Copy-Item $log "$base\and_copy.log" -Force -ErrorAction SilentlyContinue
    $line = (Select-String -Path "$base\and_copy.log" -Pattern "\[QA-VIEW\]" -Encoding UTF8 |
             Select-Object -Last 1).Line
  }
  $ratio = 1.0
  if ($line -and $line -match "ratio=([0-9.]+)") { $ratio = [double]$Matches[1] }
  # Where the Flutter view sits inside the physical display. uiautomator reports
  # it, and it is NOT (0,0) on this handset (display cutout on the left in
  # landscape), so every tap has to be offset by it.
  $offX = 0; $offY = 0
  $dump = adb shell uiautomator dump /sdcard/_qa_ui.xml 2>$null | Out-Null
  adb pull /sdcard/_qa_ui.xml "$base\and_ui.xml" 2>$null | Out-Null
  if (Test-Path "$base\and_ui.xml") {
    $xml = Get-Content "$base\and_ui.xml" -Raw -Encoding UTF8
    if ($xml -match 'package="com\.kalakchi\.ramyar\.pos"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' -or
        $xml -match 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*package="com\.kalakchi\.ramyar\.pos"') {
      $offX = [int]$Matches[1]; $offY = [int]$Matches[2]
    }
  }
  return @{ ratio = $ratio; offX = $offX; offY = $offY; line = $line }
}

function Convert-To-Device([double]$lx, [double]$ly, $info) {
  return @(
    [int]($info.offX + [Math]::Round($lx * $info.ratio)),
    [int]($info.offY + [Math]::Round($ly * $info.ratio))
  )
}

switch ($Cmd) {
  "view" {
    $i = Get-ViewInfo
    Write-Output "$($i.line)"
    Write-Output "offset=$($i.offX),$($i.offY)"
  }
  "screen" {
    $all = @()
    if (Test-Path $log) {
      Copy-Item $log "$base\and_copy.log" -Force -ErrorAction SilentlyContinue
      $all = Select-String -Path "$base\and_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
             Select-Object -Last $Count | ForEach-Object { $_.Line }
    }
    $all
  }
  "err" {
    if (Test-Path $log) {
      Copy-Item $log "$base\and_copy.log" -Force -ErrorAction SilentlyContinue
      Select-String -Path "$base\and_copy.log" -Pattern "\[QA-ERROR\]" -Encoding UTF8 |
        Select-Object -Last $Count | ForEach-Object { $_.Line }
    }
  }
  "tap" {
    $i = Get-ViewInfo
    $p = Convert-To-Device $X $Y $i
    Write-Output "tap $($p[0]),$($p[1])"
    adb shell input tap $p[0] $p[1] | Out-Null
  }
  "taptext" {
    $i = Get-ViewInfo
    $digest = Get-Digest
    if (-not $digest) { Write-Output "NO-DIGEST"; exit 1 }
    # Labels look like: |some text@x,y
    $rx = [regex]'\|\Q' + [regex]::Escape($Text) + '\E@(-?\d+),(-?\d+)'
    $m = [regex]::Match($digest, $rx)
    if (-not $m.Success) { Write-Output "NOT-FIND '$Text'"; exit 2 }
    $p = Convert-To-Device ([double]$m.Groups[1].Value) ([double]$m.Groups[2].Value) $i
    Write-Output "taptext '$Text' -> $($p[0]),$($p[1])"
    adb shell input tap $p[0] $p[1] | Out-Null
  }
  "swipe" {
    $i = Get-ViewInfo
    $a = Convert-To-Device $X1 $Y1 $i
    $b = Convert-To-Device $X2 $Y2 $i
    Write-Output "swipe $($a[0]),$($a[1]) -> $($b[0]),$($b[1])"
    adb shell input swipe $a[0] $a[1] $b[0] $b[1] $Ms | Out-Null
  }
  "back" { adb shell input keyevent 4 | Out-Null }
  default { Write-Output "UNKNOWN $Cmd" }
}
