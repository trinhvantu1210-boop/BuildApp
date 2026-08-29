@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ===================================================
echo     DONG GOI CAC TINH NANG (JSON -^> I.BIN)
echo ===================================================
echo.
python tools/edit_catalog.py --import
echo.
echo ===================================================
echo   XONG! Cac file i.bin da duoc cap nhat vao App.
echo ===================================================
pause
