@echo off
rem ===========================================================================
rem  O2Jam Offline Client -- double-click installer for Windows
rem
rem  No Python, no downloads to install, no admin rights. Windows PowerShell
rem  ships with Windows, so this .cmd is enough to get the whole thing going.
rem
rem  It runs install.ps1 next to it if there is one, otherwise it fetches
rem  install.ps1 from the project and runs that.
rem ===========================================================================
setlocal EnableExtensions
title O2Jam Offline Client - installer

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

set "SCRIPT=%~dp0install.ps1"
if exist "%SCRIPT%" goto run

echo.
echo   install.ps1 is not next to this file -- fetching it from GitHub ...
set "SCRIPT=%TEMP%\o2jam-install.ps1"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/Dextroid17/o2jam-offline-client/main/install.ps1' -OutFile '%SCRIPT%'"
if errorlevel 1 (
  echo.
  echo   Could not download install.ps1. Check your internet connection,
  echo   or grab it by hand from:
  echo     https://github.com/Dextroid17/o2jam-offline-client
  echo.
  pause
  exit /b 1
)

:run
echo.
echo   running the O2Jam installer -- this can take a while ...
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo   Finished, exit code 0. If you skipped the build, you can run it later
  echo   from the install folder:  native\build-cxo2.sh via git-bash, or see
  echo   docs\SETUP.md.
) else (
  echo   The installer exited with code %RC%. Scroll up for the first error;
  echo   docs\SETUP.md lists the ones that actually happen.
)
echo.
pause
exit /b %RC%
