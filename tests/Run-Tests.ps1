#requires -Version 5.1
[CmdletBinding()]
param([string]$ModulePath, [string]$ReportPath)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $scriptDirectory 'test-results.local.json' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $scriptDirectory '..\src\Launcher.Core.psm1'
    if (-not (Test-Path -LiteralPath $ModulePath)) { $ModulePath = Join-Path $scriptDirectory '..\skills\codex-windows-proxy\assets\launcher\Launcher.Core.psm1' }
}
Import-Module $ModulePath -Force -DisableNameChecking
$script:cases = @()
function Assert-True { param([bool]$Value, [string]$Message = 'Assertion failed') if (-not $Value) { throw $Message } }
function Assert-Equal { param($Actual, $Expected) if ($Actual -cne $Expected) { throw "Expected [$Expected], received [$Actual]." } }
function Assert-Throws { param([scriptblock]$Action) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; if (-not $threw) { throw 'Expected an exception.' } }
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action | Out-Null; $script:cases += [pscustomobject]@{ Name = $Name; Passed = $true }; Write-Host ('PASS ' + $Name) }
    catch { $script:cases += [pscustomobject]@{ Name = $Name; Passed = $false; Error = $_.Exception.Message }; Write-Host ('FAIL ' + $Name + ': ' + $_.Exception.Message) }
}
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$temporary = Join-Path $temporaryParent ('cpl-tests-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    Test-Case 'Port boundaries and absent input never become a guessed default' {
        foreach ($port in @(1, 65535, '31415')) { Assert-Equal (Assert-CplPort $port) ([int]$port) }
        foreach ($bad in @($null, '', ' ', 0, -1, 65536, $true, '7897;exit', '1.5', '1e3')) { Assert-Throws { Assert-CplPort $bad } }
    }
    Test-Case 'Proxy scheme and scope validation reject remote endpoints' {
        Assert-Equal (New-CplConfiguration -ProxyPort 12345).proxyHost '127.0.0.1'
        Assert-Throws { New-CplConfiguration -ProxyPort 12345 -ProxyHost 'proxy.example.com' }
    }
    Test-Case 'Configuration roundtrip, edit and malformed JSON preserve existing files' {
        $unicode = -join @([char]0x6D4B, [char]0x8BD5)
        $directory = Join-Path $temporary ($unicode + " folder's space")
        [void][IO.Directory]::CreateDirectory($directory)
        $path = Join-Path $directory 'launcher.config.json'
        Write-CplConfiguration -Path $path -Configuration (New-CplConfiguration 12345)
        Assert-Equal (Read-CplConfiguration $path).proxyPort 12345
        Write-CplConfiguration -Path $path -Configuration (New-CplConfiguration 54321)
        Assert-Equal (Read-CplConfiguration $path).proxyPort 54321
        $before = [IO.File]::ReadAllText($path)
        Assert-Throws { Write-CplConfiguration -Path $path -Configuration ([pscustomobject]@{proxyPort = 0; proxyHost = '127.0.0.1'}) }
        Assert-Equal ([IO.File]::ReadAllText($path)) $before
        [IO.File]::WriteAllText($path, '{ broken json')
        Assert-Throws { Read-CplConfiguration $path }
        Assert-Equal ([IO.File]::ReadAllText($path)) '{ broken json'
    }
    Test-Case 'Package resolution cannot escape the registered directory' {
        $root = Join-Path $temporary 'package'
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'app'))
        [IO.File]::WriteAllText((Join-Path $root 'app\client.exe'), 'fixture: never executed')
        [IO.File]::WriteAllText((Join-Path $temporary 'outside.exe'), 'fixture: never executed')
        Assert-Equal (Resolve-CplExecutable $root 'app\client.exe') (Join-Path $root 'app\client.exe')
        Assert-Throws { Resolve-CplExecutable $root '..\outside.exe' }
        Assert-Throws { Resolve-CplExecutable $root (Join-Path $temporary 'outside.exe') }
        Assert-Throws { Resolve-CplExecutable $root 'app\missing.exe' }
    }
    Test-Case 'Proxy is inherited by a real helper without altering parent or certificate settings' {
        $names = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'SSL_CERT_FILE', 'CODEX_HOME')
        $before = @{}
        foreach ($name in $names) { $before[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        try {
            [Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://parent.invalid:9', 'Process')
            [Environment]::SetEnvironmentVariable('ALL_PROXY', 'socks5://parent.invalid:8', 'Process')
            [Environment]::SetEnvironmentVariable('NO_PROXY', '*', 'Process')
            [Environment]::SetEnvironmentVariable('SSL_CERT_FILE', 'preserved-cert-path', 'Process')
            [Environment]::SetEnvironmentVariable('CODEX_HOME', 'preserved-codex-path', 'Process')
            $powershell = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $package = [pscustomobject]@{ Executable = $powershell; InstallLocation = $temporary }
            $info = New-CplProcessStartInfo -Package $package -Configuration (New-CplConfiguration 23456)
            Assert-Equal $info.Arguments '--proxy-server=http://127.0.0.1:23456'
            $code = '[pscustomobject]@{Http=$env:HTTP_PROXY;Https=$env:HTTPS_PROXY;All=$env:ALL_PROXY;No=$env:NO_PROXY;Cert=$env:SSL_CERT_FILE;Codex=$env:CODEX_HOME}|ConvertTo-Json -Compress'
            $info.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
            $info.CreateNoWindow = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
            $child = [Diagnostics.Process]::Start($info)
            try {
                $outTask = $child.StandardOutput.ReadToEndAsync(); $errTask = $child.StandardError.ReadToEndAsync()
                Assert-True ($child.WaitForExit(15000)) 'Test helper did not finish in time.'
                $record = $outTask.GetAwaiter().GetResult() | ConvertFrom-Json
                Assert-Equal $child.ExitCode 0
                Assert-Equal $record.Http 'http://127.0.0.1:23456'
                Assert-Equal $record.Https 'http://127.0.0.1:23456'
                Assert-True ([string]::IsNullOrEmpty($record.All)) 'Conflicting ALL_PROXY leaked to the child.'
                Assert-Equal $record.No 'localhost,127.0.0.1,::1'
                Assert-Equal $record.Cert 'preserved-cert-path'
                Assert-Equal $record.Codex 'preserved-codex-path'
                Assert-Equal $env:HTTP_PROXY 'http://parent.invalid:9'
                Assert-Equal $env:ALL_PROXY 'socks5://parent.invalid:8'
                Assert-Equal $env:NO_PROXY '*'
            } finally { if (-not $child.HasExited) { $child.Kill() }; $child.Dispose() }
        } finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $before[$name], 'Process') } }
    }
    Test-Case 'Local Schannel credential errors are classified separately' {
        $errorValue = New-Object ComponentModel.Win32Exception(-2146893042)
        Assert-Equal (Get-CplFailure -Exception $errorValue -Stage 'Tls').Category 'LocalTlsCredentialError'
    }
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class CplFakeProxy : IDisposable {
    private readonly TcpListener listener; private readonly Thread worker;
    private TcpClient client; private readonly string mode;
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public CplFakeProxy(string value) {
        mode = value; listener = new TcpListener(IPAddress.Loopback, 0); listener.Start();
        worker = new Thread(Work); worker.IsBackground = true; worker.Start();
    }
    private void Work() {
        try {
            client = listener.AcceptTcpClient(); client.ReceiveTimeout = 1000;
            var stream = client.GetStream(); var header = new StringBuilder();
            while (header.Length < 8192 && !header.ToString().EndsWith("\r\n\r\n")) {
                int next = stream.ReadByte(); if (next < 0) return; header.Append((char)next);
            }
            if (mode == "silent") { Thread.Sleep(1200); return; }
            string reply = mode == "reject" ? "HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n" :
                mode == "notproxy" ? "HTTP/1.1 404 Not a proxy\r\nX-Debug: HTTP/1.1 200\r\n\r\n" : "HTTP/1.1 200 Connection established\r\n\r\n";
            byte[] bytes = Encoding.ASCII.GetBytes(reply);
            if (mode == "drip") {
                foreach (byte value in bytes) { stream.WriteByte(value); Thread.Sleep(50); }
            } else { stream.Write(bytes, 0, bytes.Length); }
            if (mode == "tlsjunk") { bytes = Encoding.ASCII.GetBytes("not a TLS record"); stream.Write(bytes, 0, bytes.Length); }
        } catch { } finally { if (client != null) client.Close(); }
    }
    public void Dispose() { listener.Stop(); if (client != null) client.Close(); worker.Join(1500); }
}
'@
    Test-Case 'A live non-proxy/rejected port is not reported as usable' {
        foreach ($mode in @('reject', 'notproxy')) {
            $server = New-Object CplFakeProxy($mode)
            try {
                $result = Invoke-CplNetworkProbe -Configuration (New-CplConfiguration $server.Port) -TimeoutMs 1000
                Assert-True $result.ProxyTcp
                Assert-True (-not $result.HttpConnect)
                Assert-True (-not $result.Success)
                Assert-Equal $result.Failure.Stage 'HttpConnect'
            } finally { $server.Dispose() }
        }
    }
    Test-Case 'CONNECT acceptance without TLS is a TLS-stage failure, not TCP success' {
        $server = New-Object CplFakeProxy('tlsjunk')
        try {
            $result = Invoke-CplNetworkProbe -Configuration (New-CplConfiguration $server.Port) -TimeoutMs 1000
            Assert-True $result.ProxyTcp
            Assert-True $result.HttpConnect
            Assert-True (-not $result.Tls)
            Assert-True (-not $result.Success)
            Assert-Equal $result.Failure.Stage 'Tls'
            Assert-Equal $result.ApplicationVerification 'NotTested'
        } finally { $server.Dispose() }
    }
    Test-Case 'Silent and dripping proxy headers respect a total stage deadline' {
        foreach ($mode in @('silent', 'drip')) {
            $server = New-Object CplFakeProxy($mode)
            try {
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $result = Invoke-CplNetworkProbe -Configuration (New-CplConfiguration $server.Port) -TimeoutMs 200
                Assert-True (-not $result.Success)
                Assert-Equal $result.Failure.Stage 'HttpConnect'
                Assert-True ($timer.ElapsedMilliseconds -lt 2500) 'Header timeout was not bounded.'
            } finally { $server.Dispose() }
        }
    }
    Test-Case 'CheckOnly with missing configuration exits nonzero without creating it' {
        $entry = Join-Path (Split-Path -Parent $ModulePath) 'Launcher.ps1'
        $missing = Join-Path $temporary 'never-created.json'
        $powershell = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $raw = & $powershell -NoProfile -ExecutionPolicy Bypass -File $entry -ConfigPath $missing -CheckOnly
        Assert-Equal $LASTEXITCODE 20
        $value = ($raw -join "`n") | ConvertFrom-Json
        Assert-True (-not $value.Success)
        Assert-True (-not (Test-Path -LiteralPath $missing))
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    if (-not $resolved.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^cpl-tests-[0-9a-f]{32}$') { throw 'Refusing unexpected test cleanup target.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$report = [ordered]@{ Suite = 'Launcher core'; Passed = @($script:cases | Where-Object Passed).Count; Failed = @($script:cases | Where-Object { -not $_.Passed }).Count; Cases = $script:cases }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host ($report.Passed.ToString() + ' passed; ' + $report.Failed + ' failed.')
if ($report.Failed -gt 0) { exit 1 }
exit 0
