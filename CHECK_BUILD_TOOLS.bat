@echo off
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

echo Checking Visual Studio C++ build tools...
echo.

if not exist "%VSWHERE%" (
    echo NOT FOUND: Visual Studio Installer / Build Tools.
    echo.
    echo Install Visual Studio 2022 Build Tools and select:
    echo   [x] Desktop development with C++
    echo   [x] MSVC v143 x64/x86 build tools
    echo   [x] Windows 10 or Windows 11 SDK
    echo.
    pause
    exit /b 1
)

"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%TEMP%\scropts_vs.txt"
set /p VSPATH=<"%TEMP%\scropts_vs.txt"
del "%TEMP%\scropts_vs.txt" >nul 2>&1

if "%VSPATH%"=="" (
    echo Visual Studio is installed, but the C++ build workload is missing.
    echo Open Visual Studio Installer ^> Modify and add:
    echo   [x] Desktop development with C++
    echo.
    pause
    exit /b 1
)

echo FOUND:
echo %VSPATH%
echo.
echo C++ build tools look available.
pause

