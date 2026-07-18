@echo off
setlocal

:: Auto-Elevation: Check for admin rights and elevate via PowerShell if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrative privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%0' -ArgumentList 'Elevated' -Verb RunAs"
    exit /b
)

:: Get the directory where this .bat file is located
set "SCRIPT_DIR=%~dp0"

:: Launch the perfectly structured .ps1 file
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%RAM_Flusher.ps1"

echo.
echo Press any key to close...
pause >nul