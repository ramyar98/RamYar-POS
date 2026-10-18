@echo off
REM Launch RAMYAR POS on Windows desktop in debug mode, with hot reload.
REM
REM Convenience wrapper: sets RAMYAR_BUILD_TYPE=Debug and runs `flutter run -d windows`.
REM `windows\CMakeLists.txt` finds the MSVC toolchain, Windows SDK and Ninja by
REM itself; the script is only to start from anywhere on this machine cleanly.
setlocal
cd /d "%~dp0"

set "RAMYAR_BUILD_TYPE=Debug"

echo Launching RAMYAR POS on Windows (debug, hot reload enabled)...
flutter run -d windows 2>&1 | tee "%~dp0run_windows_dev.log"
exit /b %errorlevel%
