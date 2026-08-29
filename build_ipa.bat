@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_ipa.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ====================================================================
    echo Neu gap van de, hay chay truc tiep file build_ipa.ps1 bang PowerShell.
    echo ====================================================================
)
echo.
pause
