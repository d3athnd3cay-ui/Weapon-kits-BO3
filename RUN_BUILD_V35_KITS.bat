@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Audited-Scropts.ps1" -TestProfile kits
echo.
pause
