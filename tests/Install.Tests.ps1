#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $scriptDirectory 'install-results.local.json' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$skill = [IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\skills\codex-windows-proxy'))
$script:cases = @()
function Assert-True { param([bool]$Value, [string]$Message = 'Assertion failed') if (-not $Value) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; if (-not $threw) { throw 'Expected an exception.' } }
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action | Out-Null; $script:cases += [pscustomobject]@{Name = $Name; Passed = $true}; Write-Host ('PASS ' + $Name) }
    catch { $script:cases += [pscustomobject]@{Name = $Name; Passed = $false; Error = $_.Exception.Message}; Write-Host ('FAIL ' + $Name + ': ' + $_.Exception.Message) }
}
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$temporary = Join-Path $temporaryParent ('cpl-install-tests-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$installer = Join-Path $skill 'scripts\Install-Launcher.ps1'
$uninstaller = Join-Path $skill 'scripts\Uninstall-Launcher.ps1'
try {
    Test-Case 'Invalid user port fails before installing any files' {
        $target = Join-Path $temporary 'invalid'
        Assert-Throws { & $installer -ProxyPort 0 -InstallDirectory $target -NoShortcut }
        Assert-True (-not (Test-Path -LiteralPath $target))
    }
    Test-Case 'Install and reinstall use the supplied port without launching or claiming connection' {
        $target = Join-Path $temporary "user's folder with space"
        $raw = & $installer -ProxyPort 23456 -InstallDirectory $target -NoShortcut
        $installed = ($raw -join "`n") | ConvertFrom-Json
        Assert-True $installed.FilesInstalled
        Assert-True (-not $installed.ClientLaunched)
        Assert-True (-not $installed.ConnectivityVerified)
        Assert-True ($installed.ProxyPort -eq 23456)
        $configuration = Get-Content -LiteralPath (Join-Path $target 'launcher.config.json') -Raw | ConvertFrom-Json
        Assert-True ($configuration.proxyPort -eq 23456)
        & $installer -ProxyPort 34567 -InstallDirectory $target -NoShortcut | Out-Null
        $configuration = Get-Content -LiteralPath (Join-Path $target 'launcher.config.json') -Raw | ConvertFrom-Json
        Assert-True ($configuration.proxyPort -eq 34567)
    }
    Test-Case 'Installer rejects a nonempty unowned target' {
        $target = Join-Path $temporary 'unowned'
        [void][IO.Directory]::CreateDirectory($target)
        [IO.File]::WriteAllText((Join-Path $target 'keep.txt'), 'user data')
        Assert-Throws { & $installer -ProxyPort 23456 -InstallDirectory $target -NoShortcut }
        Assert-True (([IO.File]::ReadAllText((Join-Path $target 'keep.txt'))) -eq 'user data')
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'installed-files.json')))
    }
    Test-Case 'A tampered bundled payload fails checksum validation before installation' {
        $copy = Join-Path $temporary 'skill-copy'
        Copy-Item -LiteralPath $skill -Destination $copy -Recurse
        Add-Content -LiteralPath (Join-Path $copy 'assets\launcher\Launcher.ps1') -Value '# tampered fixture'
        $target = Join-Path $temporary 'tampered-target'
        Assert-Throws { & (Join-Path $copy 'scripts\Install-Launcher.ps1') -ProxyPort 23456 -InstallDirectory $target -NoShortcut }
        Assert-True (-not (Test-Path -LiteralPath $target))
    }
    Test-Case 'Uninstall preserves configuration and unrelated files, optional removal stays bounded' {
        $target = Join-Path $temporary "user's folder with space"
        $foreign = Join-Path $target 'keep-my-file.txt'
        [IO.File]::WriteAllText($foreign, 'user data')
        & $uninstaller -InstallDirectory $target | Out-Null
        Assert-True (Test-Path -LiteralPath (Join-Path $target 'launcher.config.json'))
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'Launcher.ps1')))
        Assert-True (Test-Path -LiteralPath $foreign)
        & $uninstaller -InstallDirectory $target -RemoveConfiguration | Out-Null
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'launcher.config.json')))
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'installed-files.json')))
        Assert-True (([IO.File]::ReadAllText($foreign)) -eq 'user data')
    }
    Test-Case 'Uninstaller refuses a directory without an ownership marker' {
        $target = Join-Path $temporary 'unowned'
        Assert-Throws { & $uninstaller -InstallDirectory $target -RemoveConfiguration }
        Assert-True (Test-Path -LiteralPath (Join-Path $target 'keep.txt'))
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    if (-not $resolved.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^cpl-install-tests-[0-9a-f]{32}$') { throw 'Refusing unexpected test cleanup target.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$report = [ordered]@{Suite = 'Skill install'; Passed = @($script:cases | Where-Object Passed).Count; Failed = @($script:cases | Where-Object {-not $_.Passed}).Count; Cases = $script:cases}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host ($report.Passed.ToString() + ' passed; ' + $report.Failed + ' failed.')
if ($report.Failed -gt 0) {exit 1}
exit 0
