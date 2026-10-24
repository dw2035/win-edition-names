@echo off
rem ============================================================
rem  lookup.bat - launcher for client\lookup.ps1  (Windows names)
rem
rem  Double-click : run with defaults, wait for a key at the end
rem  With args    : pass them through, no pause, returns exit code
rem                 e.g.  lookup.bat -List
rem                       lookup.bat -Edition EnterpriseS
rem                       lookup.bat -Json
rem  Pure ASCII file.
rem ============================================================
setlocal
set "PS1=%~dp0client\lookup.ps1"

if not exist "%PS1%" (
    echo [ERROR] client\lookup.ps1 not found next to this .bat
    echo         expected: "%PS1%"
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

if "%~1"=="" (
    echo.
    echo [exit code: %RC%]
    echo Press any key to close...
    pause >nul
)

endlocal & exit /b %RC%
