@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-build.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
  echo Publish build FAILED.
) else (
  echo Publish build SUCCEEDED.
)
echo.

pause
exit /b %EXITCODE%
