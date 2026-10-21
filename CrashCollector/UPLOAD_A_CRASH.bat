@echo off
setlocal
cd /d "%~dp0"
echo.
echo BO3 Crash Collector - local files only, no auto-upload
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0COLLECT_BO3_CRASH.ps1"
echo.
pause
