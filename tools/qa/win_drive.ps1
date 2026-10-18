# Executes a UTF-8 command script against the Windows RAMYAR POS app.
#
# The Windows twin of drive_android.ps1. Reads a file where every line is one
# action, so Kurdish label text is never passed through a command line (which
# mangles it). Actions:
#
#   screen [n]        print the last n screen digests
#   err [n]           print the last n framework errors the app captured
#   view              print the Flutter view size and the coordinate mapping
#   tap <x> <y>       click at LOGICAL view coordinates
#   taptext <label>   click the centre of a label from the latest digest
#   wait <seconds>    sleep
#   settle <seconds>  wait, then print the screen digest (the usual step)
#   key <KeyName>...  send keys (Enter, Tab, Escape, ...)
#   type <text>       type ASCII text
#   shot <name>       capture the window to the shots folder (for the record)
#
# Blank lines and lines starting with '#' are ignored.
param(
  [Parameter(Mandatory = $true)][string]$Script,
  [switch]$StopOnError
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
$base = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode"
$ui = Join-Path $PSScriptRoot "win_ui.ps1"
$log = "$base\win_run.log"
$shotDir = "$base\shots"

function Copy-Log {
  Copy-Item $log "$base\win_copy.log" -Force -ErrorAction SilentlyContinue
}

function Get-Digest {
  Copy-Log
  if (-not (Test-Path "$base\win_copy.log")) { return "" }
  $m = Select-String -Path "$base\win_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
       Select-Object -Last 1
  if ($m -eq $null) { return "" }
  return $m.Line
}

# The digest is in logical pixels inside the Flutter view; the mouse wants
# screen pixels. Deriving the mapping from the window itself (rather than
# assuming a scale) is what keeps this working when Windows is at 125% or 150%
# and when the border is not the width it was yesterday.
function Get-Mapping {
  $vline = ""
  Copy-Log
  if (Test-Path "$base\win_copy.log") {
    $vline = (Select-String -Path "$base\win_copy.log" -Pattern "\[QA-VIEW\]" -Encoding UTF8 |
              Select-Object -Last 1).Line
  }
  $lw = 0.0; $lh = 0.0
  if ($vline -and $vline -match "logical=(\d+)x(\d+)") {
    $lw = [double]$Matches[1]; $lh = [double]$Matches[2]
  }
  $size = (& $ui size) -join ""
  $ox = 0; $oy = 0; $cw = 0.0; $ch = 0.0
  if ($size -match "client origin (-?\d+),(-?\d+) client (\d+)x(\d+)") {
    $ox = [int]$Matches[1]; $oy = [int]$Matches[2]
    $cw = [double]$Matches[3]; $ch = [double]$Matches[4]
  }
  $sx = if ($lw -gt 0) { $cw / $lw } else { 1.0 }
  $sy = if ($lh -gt 0) { $ch / $lh } else { 1.0 }
  # win_ui.ps1 `click` adds the window origin itself, so hand it client-relative
  # coordinates and take the window origin back off.
  $winOx = 0; $winOy = 0
  if ($size -match "window (-?\d+),(-?\d+) ") { $winOx = [int]$Matches[1]; $winOy = [int]$Matches[2] }
  return @{
    scaleX = $sx; scaleY = $sy
    offX = $ox - $winOx; offY = $oy - $winOy
    line = $vline; size = $size
  }
}

function To-Click([double]$lx, [double]$ly, $m) {
  # What win_ui.ps1 wants: (screen - windowOrigin).
  return @(
    [int][Math]::Round($m.offX + $lx * $m.scaleX),
    [int][Math]::Round($m.offY + $ly * $m.scaleY)
  )
}

$failures = 0
$map = $null
foreach ($raw in [System.IO.File]::ReadAllLines($Script, [System.Text.Encoding]::UTF8)) {
  $line = $raw.Trim()
  if ($line -eq "" -or $line.StartsWith("#")) { continue }
  $parts = $line -split '\s+', 2
  $cmd = $parts[0].ToLower()
  $arg = if ($parts.Length -gt 1) { $parts[1] } else { ""
  }
  Write-Output ""
  Write-Output ">> $line"
  switch ($cmd) {
    "view"    { $map = Get-Mapping; Write-Output "$($map.line)"; Write-Output "$($map.size) -> click offset $($map.offX),$($map.offY) scale $($map.scaleX),$($map.scaleY)" }
    "screen"  {
      Copy-Log
      $n = if ($arg -eq "") { 1 } else { [int]$arg }
      Select-String -Path "$base\win_copy.log" -Pattern "\[QA-SCREEN\]" -Encoding UTF8 |
        Select-Object -Last $n | ForEach-Object { $_.Line }
    }
    "err"     {
      Copy-Log
      $n = if ($arg -eq "") { 10 } else { [int]$arg }
      $e = Select-String -Path "$base\win_copy.log" -Pattern "\[QA-ERROR\]" -Encoding UTF8 |
           Select-Object -Last $n | ForEach-Object { $_.Line }
      if ($e) { $e } else { Write-Output "(no errors)" }
    }
    "wait"    { Start-Sleep -Milliseconds ([int]([double]$arg * 1000)) }
    "settle"  {
      Start-Sleep -Milliseconds ([int]([double]$arg * 1000))
      Write-Output (Get-Digest)
    }
    "tap"     {
      if ($null -eq $map) { $map = Get-Mapping }
      $xy = $arg -split '\s+'
      $p = To-Click ([double]$xy[0]) ([double]$xy[1]) $map
      Write-Output "   -> click $($p[0]),$($p[1])"
      & $ui click $p[0] $p[1] | Out-Null
    }
    "taptext" {
      if ($null -eq $map) { $map = Get-Mapping }
      $digest = Get-Digest
      $pattern = '\|' + [regex]::Escape($arg) + '@(-?\d+),(-?\d+)'
      $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
      $m = $rx.Match($digest)
      if (-not $m.Success) {
        Write-Output "   NOT-FIND '$arg'"
        $failures++
        if ($StopOnError) { break }
        continue
      }
      $p = To-Click ([double]$m.Groups[1].Value) ([double]$m.Groups[2].Value) $map
      Write-Output "   -> click $($p[0]),$($p[1])"
      & $ui click $p[0] $p[1] | Out-Null
    }
    "key"     {
      $keys = if ($arg -eq "") { @("Enter") } else { @($arg -split '\s+') }
      & $ui key @keys | Out-Null
    }
    "release" { & $ui release | Out-Null }
    "type"    { & $ui type $arg | Out-Null }
    "focus"   { & $ui focus | Out-Null }
    "shot"    {
      New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
      & $ui shot "$shotDir\$arg.png" | Out-Null
      Write-Output "   -> shots\$arg.png"
    }
    default   { Write-Output "   UNKNOWN COMMAND '$cmd'" }
  }
}
Write-Output ""
Write-Output "== done, $failures unresolved =="