@echo off
rem ============================================================
rem  office.bat - launcher for client\office-lookup.ps1  (Office names)
rem
rem  Double-click : run with defaults, wait for a key at the end
rem  With args    : pass them through, no pause, returns exit code
rem                 e.g.  office.bat -List
rem                       office.bat -Name ProPlus2021Volume
rem                       office.bat -Json
rem  Pure ASCII file.
rem ============================================================
setlocal
set "PS1=%~dp0client\office-lookup.ps1"

if not exist "%PS1%" (
    echo [ERROR] client\office-lookup.ps1 not found next to this .bat
    echo         expected: "%PS1%"
    echo.
    pause
    exit /b 1
)

if not "%~1"=="" goto :withargs
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Interactive
goto :done
:withargs
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
:done
set "RC=%ERRORLEVEL%"

if "%~1"=="" (
    echo.
    echo [exit code: %RC%]
    echo Press any key to close...
    pause >nul
)

endlocal & exit /b %RC%
