#requires -Version 5.1
[CmdletBinding()]
param([object]$ProxyPort, [string]$InstallDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexProxyLauncher\installed'), [switch]$NoShortcut)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = [IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\assets\launcher'))
Import-Module (Join-Path $payload 'Launcher.Core.psm1') -Force -DisableNameChecking
if (-not $PSBoundParameters.ContainsKey('ProxyPort')) { $ProxyPort = Read-Host 'Enter your local HTTP/Mixed proxy port (required; no default)' }
$configuration = New-CplConfiguration -ProxyPort $ProxyPort
$target = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\', '/')
if ($target -eq [IO.Path]::GetPathRoot($target).TrimEnd('\', '/')) { throw 'A drive root cannot be an installation directory.' }
$markerPath = Join-Path $target 'installed-files.json'
$previous = $null
if (Test-Path -LiteralPath $target) {
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        $previous = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($previous.product -ne 'CodexProxyLauncher' -or $previous.schemaVersion -ne 1) { throw 'Installation ownership marker is invalid.' }
    } elseif (@(Get-ChildItem -LiteralPath $target -Force).Count -gt 0) { throw 'The target is not an owned launcher installation and is not empty.' }
}
$files = @('Launcher.Core.psm1', 'Launcher.ps1', 'Codex Proxy Launcher.cmd', 'Configure Proxy.cmd', 'Check Proxy.cmd', 'launcher.config.example.json', 'UPSTREAM.json')
$upstream = Get-Content -LiteralPath (Join-Path $payload 'UPSTREAM.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($name in $files) {
    $source = Join-Path $payload $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Bundled payload is incomplete: $name" }
    if ($name -ne 'UPSTREAM.json') {
        $expected = $upstream.sha256.PSObject.Properties[$name]
        if ($null -eq $expected -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $expected.Value) { throw "Bundled payload checksum failed: $name" }
    }
}
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Proxy Launcher.lnk'
if (-not $NoShortcut -and (Test-Path -LiteralPath $shortcutPath)) {
    $shell = New-Object -ComObject WScript.Shell
    $existingLink = $shell.CreateShortcut($shortcutPath)
    $ownScript = Join-Path $target 'Launcher.ps1'
    if ($existingLink.Arguments.IndexOf($ownScript, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'A different shortcut already uses this name. It was not overwritten.' }
}
[void][IO.Directory]::CreateDirectory($target)
# Write the ownership marker first so a later interrupted install remains safely removable.
$ownedShortcut = $null
if ($null -ne $previous -and $null -ne $previous.PSObject.Properties['shortcut']) { $ownedShortcut = $previous.shortcut }
if (-not $NoShortcut) { $ownedShortcut = $shortcutPath }
$marker = [ordered]@{ product = 'CodexProxyLauncher'; schemaVersion = 1; version = $upstream.version; shortcut = $ownedShortcut }
[IO.File]::WriteAllText($markerPath, ($marker | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
foreach ($name in $files) { Copy-Item -LiteralPath (Join-Path $payload $name) -Destination (Join-Path $target $name) -Force }
Write-CplConfiguration -Path (Join-Path $target 'launcher.config.json') -Configuration $configuration
if (-not $NoShortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $target 'Launcher.ps1') + '"'
    $shortcut.WorkingDirectory = $target
    $shortcut.Description = 'Codex per-process local proxy launcher; does not enable system proxy.'
    $shortcut.Save()
}
[pscustomobject]@{ FilesInstalled = $true; Directory = $target; ProxyPort = $configuration.proxyPort; Shortcut = $ownedShortcut; ClientLaunched = $false; ConnectivityVerified = $false; NextStep = 'Run Check-Launcher.ps1, then manually exit the old desktop client before using the new shortcut.' } | ConvertTo-Json
