# Pulls the live Android app database (db + wal + shm) to a local folder.
# The app has to be a debuggable build for `run-as`; a release install on the
# handset cannot be read and this script says so instead of copying junk.
param(
  [string]$Package = "com.kalakchi.ramyar.pos",
  [string]$Out = "C:\Users\ArkanComputer\AppData\Local\Temp\opencode\andlive"
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
adb shell "run-as $Package sh -c 'rm -rf /data/data/$Package/qadump; mkdir -p /data/data/$Package/qadump; cp /data/data/$Package/databases/ramyar_pos.db /data/data/$Package/databases/ramyar_pos.db-wal /data/data/$Package/databases/ramyar_pos.db-shm /data/data/$Package/qadump/ 2>/dev/null; ls /data/data/$Package/qadump/'" | Out-Null
foreach ($f in @("ramyar_pos.db", "ramyar_pos.db-wal", "ramyar_pos.db-shm")) {
  $target = Join-Path $Out $f
  cmd /c "adb exec-out run-as $Package cat /data/data/$Package/qadump/$f > `"$target`""
}
$size = (Get-Item (Join-Path $Out "ramyar_pos.db") -ErrorAction SilentlyContinue).Length
if ($size -lt 1024) {
  Write-Output "FAILED: got $size bytes - the app is probably a release build (run-as denied)"
} else {
  Write-Output "OK $Out ($size bytes)"
}
