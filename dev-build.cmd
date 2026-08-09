@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-build.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
  echo Development build FAILED.
) else (
  echo Development build SUCCEEDED.
)
echo.

pause
exit /b %EXITCODE%
