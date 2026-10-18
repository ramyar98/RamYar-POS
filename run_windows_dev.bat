@echo off
REM Launch RAMYAR POS on Windows desktop in debug mode, with hot reload.
REM
REM A convenience wrapper only: it just moves to the project folder, states
REM the build mode and runs `flutter run -d windows`. That command now works
REM from any prompt on its own - windows\CMakeLists.txt finds the MSVC
REM toolchain, the Windows SDK and Ninja by itself, and Debug is the default
REM build mode - so use this when you want the app to start from somewhere
REM other than the project folder, or you simply prefer one command.
setlocal
cd /d "%~dp0"

set "RAMYAR_BUILD_TYPE=Debug"

echo Launching RAMYAR POS on Windows (debug, hot reload enabled)...
flutter run -d windows
exit /b %errorlevel%
