@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0init-env.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
  echo XIVEquip environment setup FAILED.
) else (
  echo XIVEquip environment setup SUCCEEDED.
)
echo.

pause
exit /b %EXITCODE%
