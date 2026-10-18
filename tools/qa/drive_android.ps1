# Executes a UTF-8 command script against the Android RAMYAR POS app.
#
# Reads a file where every line is one action, so label text is never passed
# through a command line (which mangles Arabic/Kurdish on Windows). Actions:
#
#   screen [n]        print the last n screen digests
#   err [n]           print the last n framework errors the app captured
#   view              print window geometry
#   tap <x> <y>       tap at LOGICAL view coordinates
#   taptext <label>   tap the centre of a label from the latest digest
#   tapxy <lx> <ly> <text>   assert-free tap at explicit logical coords
#   wait <seconds>    sleep
#   settle <seconds>  wait, then print the screen digest (the usual step)
#   swipe x1 y1 x2 y2 [ms]
#   key <keyevent>
#   shot <name>       pull a screenshot to the shots folder (for the record)
#
# Blank lines and lines starting with '#' are ignored.
param(
  [Parameter(Mandatory = $true)][string]$Script,
  [switch]$StopOnError
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$base = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode"
$log = "$base\and_run.log"

function Copy-Log {
  Copy-Item $log "$base\and_copy.log" -Force -ErrorAction SilentlyContinue
}

function Get-Digest {
  Copy-Log
  if (-not (Test-Path "$base\and_copy.log")) { return "" }
  $m = Select-String -Path "$base\and_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
       Select-Object -Last 1
  if ($m -eq $null) { return "" }
  return $m.Line
}

function Get-ViewInfo {
  Copy-Log
  $line = ""
  if (Test-Path "$base\and_copy.log") {
    $line = (Select-String -Path "$base\and_copy.log" -Pattern "\[QA-VIEW\]" -Encoding UTF8 |
             Select-Object -Last 1).Line
  }
  $ratio = 1.0
  if ($line -and $line -match "ratio=([0-9]+(?:\.[0-9]+)?)") { $ratio = [double]$Matches[1] }
  # Where the Flutter view sits inside the physical display. Not (0,0) on this
  # handset: the landscape layout is inset, so every tap needs the offset.
  $offX = 0; $offY = 0
  adb shell uiautomator dump /sdcard/_qa_ui.xml 2>$null | Out-Null
  adb pull /sdcard/_qa_ui.xml "$base\and_ui.xml" 2>$null | Out-Null
  if (Test-Path "$base\and_ui.xml") {
    $xml = Get-Content "$base\and_ui.xml" -Raw -Encoding UTF8
    $m = [regex]::Match($xml, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*package="com\.kalakchi\.ramyar\.pos"')
    if ($m.Success) { $offX = [int]$m.Groups[1].Value; $offY = [int]$m.Groups[2].Value }
    else {
      $m = [regex]::Match($xml, 'package="com\.kalakchi\.ramyar\.pos"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
      if ($m.Success) { $offX = [int]$m.Groups[1].Value; $offY = [int]$m.Groups[2].Value }
    }
  }
  return @{ ratio = $ratio; offX = $offX; offY = $offY; line = $line }
}

function To-Device([double]$lx, [double]$ly, $info) {
  return @(
    [int]($info.offX + [Math]::Round($lx * $info.ratio)),
    [int]($info.offY + [Math]::Round($ly * $info.ratio))
  )
}

$failures = 0
$info = $null
foreach ($raw in [System.IO.File]::ReadAllLines($Script, [System.Text.Encoding]::UTF8)) {
  $line = $raw.Trim()
  if ($line -eq "" -or $line.StartsWith("#")) { continue }
  $parts = $line -split '\s+', 2
  $cmd = $parts[0].ToLower()
  $arg = if ($parts.Length -gt 1) { $parts[1] } else { "" }
  Write-Output ""
  Write-Output ">> $line"
  switch ($cmd) {
    "view"    { $info = Get-ViewInfo; Write-Output "$($info.line) offset=$($info.offX),$($info.offY)" }
    "screen"  {
      Copy-Log
      $n = if ($arg -eq "") { 1 } else { [int]$arg }
      Select-String -Path "$base\and_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
        Select-Object -Last $n | ForEach-Object { $_.Line }
    }
    "err"     {
      Copy-Log
      $n = if ($arg -eq "") { 10 } else { [int]$arg }
      $e = Select-String -Path "$base\and_copy.log" -Pattern "\[QA-ERROR\]" -Encoding UTF8 |
           Select-Object -Last $n | ForEach-Object { $_.Line }
      if ($e) { $e } else { Write-Output "(no errors)" }
    }
    "wait"    { Start-Sleep -Seconds ([double]$arg) }
    "settle"  {
      Start-Sleep -Seconds ([double]$arg)
      Write-Output (Get-Digest)
    }
    "tap"     {
      if ($null -eq $info) { $info = Get-ViewInfo }
      $xy = $arg -split '\s+'
      $p = To-Device ([double]$xy[0]) ([double]$xy[1]) $info
      Write-Output "   -> device $($p[0]),$($p[1])"
      adb shell input tap $p[0] $p[1] | Out-Null
    }
    "taptext" {
      if ($null -eq $info) { $info = Get-ViewInfo }
      $digest = Get-Digest
      # A digest label looks like: |<label>@x,y  - matched with a literal
      # (Regex.Escape) label so Arabic text is never treated as a pattern.
      $pattern = '\|' + [regex]::Escape($arg) + '@(-?\d+),(-?\d+)'
      $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
      $m = $rx.Match($digest)
      if (-not $m.Success) {
        Write-Output "   NOT-FIND '$arg'"
        $failures++
        if ($StopOnError) { break }
        continue
      }
      $p = To-Device ([double]$m.Groups[1].Value) ([double]$m.Groups[2].Value) $info
      Write-Output "   -> device $($p[0]),$($p[1])"
      adb shell input tap $p[0] $p[1] | Out-Null
    }
    "swipe"   {
      if ($null -eq $info) { $info = Get-ViewInfo }
      $xy = $arg -split '\s+'
      $a = To-Device ([double]$xy[0]) ([double]$xy[1]) $info
      $b = To-Device ([double]$xy[2]) ([double]$xy[3]) $info
      $ms = if ($xy.Length -gt 4) { [int]$xy[4] } else { 300 }
      Write-Output "   -> device $($a[0]),$($a[1]) -> $($b[0]),$($b[1])"
      adb shell input swipe $a[0] $a[1] $b[0] $b[1] $ms | Out-Null
    }
    "key"     { adb shell input keyevent $arg | Out-Null }
    "shot"    {
      New-Item -ItemType Directory -Force -Path "$base\shots" | Out-Null
      adb shell screencap -p /sdcard/_qa.png | Out-Null
      adb pull /sdcard/_qa.png "$base\shots\$arg.png" 2>$null | Out-Null
      Write-Output "   -> shots\$arg.png"
    }
    default   { Write-Output "   UNKNOWN COMMAND '$cmd'" }
  }
}
Write-Output ""
Write-Output "== done, $failures unresolved =="
