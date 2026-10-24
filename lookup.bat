@echo off
rem ============================================================
rem  lookup.bat - launcher for client\lookup.ps1
rem  Resolve Windows EditionID to a friendly name. Read-only.
rem  Pure ASCII file.
rem ============================================================
setlocal
set "PS1=%~dp0client\lookup.ps1"

if not exist "%PS1%" (
    echo [ERROR] client\lookup.ps1 not found.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

echo.
echo Press any key to close...
pause >nul
endlocal
