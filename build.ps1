#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $scriptDirectory 'dist' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$skill = Join-Path $scriptDirectory 'skills\codex-windows-proxy'
$payload = Join-Path $skill 'assets\launcher'
$manifest = Get-Content -LiteralPath (Join-Path $payload 'UPSTREAM.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $manifest.sha256.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $payload $entry.Name) -Algorithm SHA256).Hash -ine $entry.Value) { throw ('Payload hash mismatch: ' + $entry.Name) }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
$zip = Join-Path $OutputDirectory ('codex-windows-proxy-skill-' + $manifest.version + '.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath @($skill, (Join-Path $scriptDirectory 'README.md'), (Join-Path $scriptDirectory 'LICENSE')) -DestinationPath $zip -CompressionLevel Optimal
$line = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), ($line + "`n"), [Text.UTF8Encoding]::new($false))
Write-Output $zip
