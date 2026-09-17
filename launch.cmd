@echo off
setlocal
if "%VIVEKA_BOOTSTRAP_NONINTERACTIVE%"=="1" (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
  exit /b %ERRORLEVEL%
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0bootstrap.ps1""'"
exit /b %ERRORLEVEL%
