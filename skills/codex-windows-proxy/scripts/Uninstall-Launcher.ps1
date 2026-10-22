#requires -Version 5.1
[CmdletBinding()]
param([string]$InstallDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexProxyLauncher\installed'), [switch]$RemoveConfiguration)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\', '/')
if ($target -eq [IO.Path]::GetPathRoot($target).TrimEnd('\', '/')) { throw 'A drive root cannot be an installation directory.' }
$markerPath = Join-Path $target 'installed-files.json'
if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'No ownership marker found. Nothing was removed.' }
$marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($marker.product -ne 'CodexProxyLauncher' -or $marker.schemaVersion -ne 1) { throw 'Ownership marker is invalid. Nothing was removed.' }
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Proxy Launcher.lnk'
if ($marker.shortcut -eq $shortcutPath -and (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.Arguments.IndexOf((Join-Path $target 'Launcher.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { Remove-Item -LiteralPath $shortcutPath -Force }
}
# Fixed owned names, never recursive deletion or arbitrary paths from the marker.
$files = @('Launcher.Core.psm1', 'Launcher.ps1', 'Codex Proxy Launcher.cmd', 'Configure Proxy.cmd', 'Check Proxy.cmd', 'launcher.config.example.json', 'UPSTREAM.json')
if ($RemoveConfiguration) { $files += @('launcher.config.json', 'installed-files.json') }
foreach ($name in $files) {
    $path = Join-Path $target $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}
if (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 0) { [IO.Directory]::Delete($target, $false) }
Write-Output 'Owned launcher files removed. Existing applications, accounts, system proxy and unrelated files were not changed.'
if (-not $RemoveConfiguration) { Write-Output 'Configuration and ownership marker kept for reinstall or later removal.' }
