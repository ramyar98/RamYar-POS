# Writes a database back to the Android app's private data directory.
#
# `adb push` cannot write into /data/data/<pkg>, and piping the bytes straight
# into `run-as sh -c 'cat > file'` silently truncates - which is worse than
# failing, because the app then opens a 99-byte database and looks like it lost
# the shop's books. So the file goes across as base64 text: `adb push` is
# reliable for text, and the device-side `base64 -d` cannot be confused by
# Windows newlines or cmd's stdin handling.
#
# The app must be stopped first. It holds the database open in WAL mode and
# would overwrite the file it is handed, and a stale -wal left behind would be
# replayed on top of a database it no longer matches.
param(
  [string]$Package = "com.kalakchi.ramyar.pos",
  # QA scratch folder (%TEMP%\opencode by default, RAMYAR_QA_BASE overrides it).
  [string]$Source = (Join-Path $(if ($env:RAMYAR_QA_BASE) { $env:RAMYAR_QA_BASE } else { Join-Path $env:TEMP "opencode" }) "andlive\ramyar_pos.db"),
  [switch]$StartApp,
  [switch]$Confirm
)
$ErrorActionPreference = "Continue"
$dir = "/data/data/$Package/databases"
$db = "$dir/ramyar_pos.db"

if (-not (Test-Path $Source)) { Write-Output "MISSING $Source"; exit 2 }
$srcLen = (Get-Item $Source).Length

$running = adb shell pidof $Package 2>$null
if ($running) {
  if (-not $Confirm) {
    Write-Output "REFUSING: $Package is running (pid $running). Re-run with -Confirm to stop it."
    exit 3
  }
  Write-Output "stopping $Package (pid $running)"
  adb shell am force-stop $Package | Out-Null
  Start-Sleep -Seconds 2
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $Source "$Source.$stamp.bak" -Force
Write-Output "local backup: $Source.$stamp.bak"

$b64 = Join-Path $env:TEMP "qa_db_$stamp.b64"
[IO.File]::WriteAllText(
  $b64,
  [Convert]::ToBase64String([IO.File]::ReadAllBytes($Source)),
  [Text.Encoding]::ASCII)
adb push $b64 /data/local/tmp/qa_db.b64 | Out-Null
adb shell "run-as $Package sh -c 'base64 -d < /data/local/tmp/qa_db.b64 > $db'" | Out-Null
adb shell "run-as $Package sh -c 'rm -f $db-wal $db-shm $db-journal; ls -l $db'" | Out-Null
adb shell rm -f /data/local/tmp/qa_db.b64 | Out-Null
Remove-Item $b64 -Force -ErrorAction SilentlyContinue

# Verify by reading the size back through the same `run-as` gate, rather than
# trusting the write.
$remote = (adb shell "run-as $Package ls -l $db" 2>$null)
if ($remote -notmatch "\s$srcLen\s") {
  Write-Output "FAILED: wrote $srcLen bytes, device reports '$remote'"
  exit 4
}
Write-Output "on-device $db is $srcLen bytes"

if ($StartApp) {
  Write-Output "starting $Package"
  adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
}