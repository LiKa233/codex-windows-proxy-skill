@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launcher.ps1" -CheckOnly %*
set "launcherExit=%errorlevel%"
echo.
echo Exit code: %launcherExit%. This checks discovery and CONNECT/TLS, not all client features.
pause
exit /b %launcherExit%
