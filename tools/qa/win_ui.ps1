# Windows desktop UI automation helpers for RAMYAR POS QA.
# Usage:
#   win_ui.ps1 shot  <out.png>          - capture the RAMYAR POS window
#   win_ui.ps1 click <x> <y>            - click at window-relative coords
#   win_ui.ps1 dclick <x> <y>           - double click
#   win_ui.ps1 rclick <x> <y>           - right click
#   win_ui.ps1 type  <text>             - type text
#   win_ui.ps1 key   <KeyName>...       - send keys (e.g. Enter, Tab, Escape)
#   win_ui.ps1 move  <x> <y>            - move mouse (hover)
#   win_ui.ps1 size                    - print window bounds
#   win_ui.ps1 focus                   - bring RAMYAR POS to the foreground
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public struct POINT { public int X, Y; }
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public static IntPtr Find(string titlePart) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      if (!IsWindowVisible(h)) return true;
      var sb = new System.Text.StringBuilder(512);
      GetWindowTextW(h, sb, 512);
      string t = sb.ToString();
      if (t.IndexOf(titlePart, StringComparison.OrdinalIgnoreCase) >= 0) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@

function Get-Win {
  $h = [W]::Find("RAMYAR POS")
  if ($h -eq [IntPtr]::Zero) {
    $h = [W]::Find("ramyar_pos")
  }
  return $h
}

$cmd = $args[0]
$h = Get-Win
if ($h -eq [IntPtr]::Zero) { Write-Output "NOWINDOW"; exit 1 }

$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$ox = $r.Left
$oy = $r.Top

function Click($x, $y, $flag) {
  [W]::SetCursorPos([int]($x), [int]($y)) | Out-Null
  Start-Sleep -Milliseconds 90
  [W]::mouse_event($flag, 0, 0, 0, [IntPtr]::Zero)   # button down
  Start-Sleep -Milliseconds 60
  # Always release. Skipping the up on the left button left the pointer stuck
  # down, and Flutter read the held press as a long press - so "click a table"
  # opened the delete-table menu instead.
  $up = switch ($flag) {
    0x0002 { 0x0004 }   # left
    0x0008 { 0x0010 }   # right
    default { $flag }
  }
  [W]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
}

switch ($cmd) {
  "shot" {
    $out = $args[1]
    $c = New-Object W+RECT
    [W]::GetClientRect($h, [ref]$c) | Out-Null
    $w = $c.Right - $c.Left
    $hh = $c.Bottom - $c.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($ox, $oy, 0, 0, (New-Object System.Drawing.Size($w, $hh)))
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "OK $out ${w}x${hh}"
  }
  "click"  { [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; Click ([int]$args[1] + $ox) ([int]$args[2] + $oy) 0x0002 }
  "dclick" { [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; Click ([int]$args[1] + $ox) ([int]$args[2] + $oy) 0x0002; Click ([int]$args[1] + $ox) ([int]$args[2] + $oy) 0x0002 }
  "rclick" { [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; Click ([int]$args[1] + $ox) ([int]$args[2] + $oy) 0x0008 }
  "move"   { [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; [W]::SetCursorPos([int]$args[1] + $ox, [int]$args[2] + $oy) | Out-Null }
  "type"   { [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250; [System.Windows.Forms.SendKeys]::SendWait($args[1]) }
  "key"    {
    [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 250
    foreach ($k in $args[1..($args.Length-1)]) { [System.Windows.Forms.SendKeys]::SendWait("{$k}"); Start-Sleep -Milliseconds 90 }
  }
  "focus"  { [W]::SetForegroundWindow($h) | Out-Null; Write-Output "OK" }
  # Safety valve: release every button without moving. A press that never got
  # its release leaves the app's gesture arena stuck, and every later tap looks
  # like it did nothing.
  "release" {
    [W]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    [W]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
    [W]::mouse_event(0x0001, 0, 0, 0, [IntPtr]::Zero)
    Write-Output "OK"
  }
  "size"   {
    $c = New-Object W+RECT
    [W]::GetClientRect($h, [ref]$c) | Out-Null
    $p = New-Object W+POINT
    $p.X = 0; $p.Y = 0
    [W]::ClientToScreen($h, [ref]$p) | Out-Null
    Write-Output ("window {0},{1} {2}x{3} | client origin {4},{5} client {6}x{7}" -f `
      $ox, $oy, ($r.Right - $r.Left), ($r.Bottom - $r.Top), $p.X, $p.Y, ($c.Right - $c.Left), ($c.Bottom - $c.Top))
  }
  default  { Write-Output "UNKNOWN $cmd" }
}
