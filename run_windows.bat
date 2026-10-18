@echo off
REM Launch RAMYAR POS on Windows desktop in release mode.
REM
REM There is nothing to set up by hand any more: windows\CMakeLists.txt finds
REM the MSVC compiler, the Windows SDK and Ninja itself and bakes the include
REM and library search paths into the build, so this works from any command
REM prompt and a plain `flutter run -d windows` needs no launcher at all.
REM
REM All this script still has to do is declare the build mode. The reason it
REM has to is in windows\CMakeLists.txt: this Flutter toolchain configures the
REM project with the single-config Ninja generator, passes no
REM -DCMAKE_BUILD_TYPE, and leaves no other trace of the requested mode, so
REM CMake cannot infer it. The default is Debug, which is what
REM `flutter run -d windows` needs - meaning that `flutter build windows
REM --release` on its own would quietly produce a debug runner. Setting
REM RAMYAR_BUILD_TYPE=Release is what makes this a real release build.
setlocal
cd /d "%~dp0"

set "RAMYAR_BUILD_TYPE=Release"

echo [1/2] Building Windows app (Release)...
flutter build windows --release 2>&1 | tee "%~dp0build_windows_release.log"
if errorlevel 1 (
  echo [ERROR] Build failed. See %~dp0build_windows_release.log
  exit /b 1
)

set "EXE=build\windows\x64\runner\ramyar_pos.exe"
if not exist "%EXE%" (
  echo [ERROR] Built exe not found: %EXE%
  exit /b 1
)

echo [2/2] Launching %EXE%
start "" "%EXE%"
exit /b 0
