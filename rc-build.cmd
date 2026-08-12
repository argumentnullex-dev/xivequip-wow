@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rc-build.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
  echo Release candidate build FAILED.
) else (
  echo Release candidate build SUCCEEDED.
)
echo.

pause
exit /b %EXITCODE%
