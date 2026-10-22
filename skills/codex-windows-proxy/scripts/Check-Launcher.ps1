#requires -Version 5.1
[CmdletBinding()]
param([string]$InstallDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexProxyLauncher\installed'))
$ErrorActionPreference = 'Stop'
$entry = Join-Path $InstallDirectory 'Launcher.ps1'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'Launcher is not installed at this location.' }
$powershell = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $entry -CheckOnly
exit $LASTEXITCODE
