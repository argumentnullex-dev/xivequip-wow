@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
  echo Build FAILED.
) else (
  echo Build SUCCEEDED.
)
echo.

pause
exit /b %EXITCODE%
