@echo off
rem ============================================================
rem  lookup.bat  -  single-file cloud client for win-edition-names
rem
rem  Flow: download client/lookup.ps1 from GitHub  ->  verify
rem        SHA256  ->  run it (interactive when no args)
rem
rem  Usage:
rem    double-click          interactive
rem    lookup.bat -List      pass args through (no pause)
rem    lookup.bat -Guide     read-only hints
rem    lookup.bat -Json      single-line JSON
rem
rem  Pure ASCII file. No admin rights required.
rem ============================================================
setlocal EnableDelayedExpansion

set "PRIMARY=https://raw.githubusercontent.com/dw2035/win-edition-names/main/client"
set "MIRROR=https://dw2035.github.io/win-edition-names/client"
set "DIR=%TEMP%\win-edition-names"
set "PS1=%DIR%\lookup.ps1"
set "SHA=%DIR%\lookup.ps1.sha256"

if not exist "%DIR%" md "%DIR%" >nul 2>&1

echo ============================================================
echo   win-edition-names  (cloud client)
echo ============================================================

set "GOT="
call :try "%PRIMARY%"
if not defined GOT call :try "%MIRROR%"
if not defined GOT goto :nonetwork
echo   source : %GOT%

if not exist "%SHA%" goto :nohash
set "EXPECT="
for /f "tokens=1" %%h in ('type "%SHA%"') do if not defined EXPECT set "EXPECT=%%h"
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%PS1%" SHA256 2^>nul') do if not defined ACTUAL set "ACTUAL=%%h"
if /i "%EXPECT%"=="%ACTUAL%" goto :run
echo.
echo [ERROR] SHA256 mismatch - refusing to run.
echo         expected : %EXPECT%
echo         actual   : %ACTUAL%
echo         The script may be corrupted or tampered with.
echo.
pause
exit /b 4

:nohash
echo   [warn] checksum file missing, running without verification.

:run
if not "%~1"=="" goto :withargs
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Interactive
set "RC=%ERRORLEVEL%"
echo.
echo [exit code: %RC%]
pause >nul
goto :done

:withargs
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
goto :done

:nonetwork
echo.
if not exist "%PS1%" goto :nocache
echo   [warn] download failed, using cached copy from a previous run.
goto :run

:nocache
echo [ERROR] cannot download the script and no cached copy exists.
echo         Check network / proxy, then try again.
echo.
pause
exit /b 3

:done
endlocal & exit /b %RC%

rem ---------- download helper ----------
:try
curl -fsSL --max-time 20 -o "%PS1%.tmp" "%~1/lookup.ps1" 2>nul
if errorlevel 1 goto :eof
curl -fsSL --max-time 20 -o "%SHA%.tmp" "%~1/lookup.ps1.sha256" 2>nul
move /y "%PS1%.tmp" "%PS1%" >nul 2>&1
if exist "%SHA%.tmp" move /y "%SHA%.tmp" "%SHA%" >nul 2>&1
set "GOT=%~1"
goto :eof
