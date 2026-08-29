@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ===================================================
echo        TOOL MA HOA FILE MOD THANH FILE .BIN
echo ===================================================
echo.
set /p infile="Nhap duong dan file Mod goc cua ban (hoac keo tha file vao day): "
set /p outdir="Chon muc tieu (1: Aim [gd], 2: Skin [sk], 3: Chams [dv]): "
set /p binname="Nhap ten file bin (vi du f12 hoac s01): "

if "%outdir%"=="1" set targetpath=ThreeOneOSFive\gd\%binname%.bin
if "%outdir%"=="2" set targetpath=ThreeOneOSFive\sk\%binname%.bin
if "%outdir%"=="3" set targetpath=ThreeOneOSFive\dv\%binname%.bin

echo.
echo Dang ma hoa file...
python tools/pack_tool.py --input %infile% --output %targetpath%
echo.
echo ===================================================
echo   XONG! File da duoc tao tai: %targetpath%
echo ===================================================
pause
