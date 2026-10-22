#requires -Version 5.1
Set-StrictMode -Version Latest
$script:CplVersion = '1.0.0-rc.1'

function Assert-CplPort {
    param([object]$Port)
    if ($null -eq $Port -or $Port -is [bool] -or ([string]$Port) -notmatch '^\d{1,5}$') {
        throw 'Enter an HTTP/Mixed proxy port from 1 to 65535. No default port is assumed.'
    }
    $number = [int]$Port
    if ($number -lt 1 -or $number -gt 65535) { throw 'Proxy port must be from 1 to 65535.' }
    return $number
}

function New-CplConfiguration {
    param([Parameter(Mandatory = $true)][object]$ProxyPort, [string]$ProxyHost = '127.0.0.1')
    if ($ProxyHost -notin @('127.0.0.1', 'localhost', '::1')) {
        throw 'This release supports an unauthenticated HTTP/Mixed proxy on the local computer only.'
    }
    return [pscustomobject][ordered]@{ schemaVersion = 1; proxyHost = $ProxyHost; proxyPort = (Assert-CplPort $ProxyPort) }
}

function Read-CplConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration not found: $Path. Run configuration first." }
    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $value -or $null -eq $value.PSObject.Properties['schemaVersion'] -or $value.schemaVersion -ne 1) {
        throw 'Unsupported configuration schema. Expected schemaVersion: 1.'
    }
    if ($null -eq $value.PSObject.Properties['proxyPort'] -or $null -eq $value.PSObject.Properties['proxyHost']) {
        throw 'Configuration must contain proxyHost and proxyPort.'
    }
    return New-CplConfiguration -ProxyPort $value.proxyPort -ProxyHost ([string]$value.proxyHost)
}

function Write-CplConfiguration {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Configuration)
    $validated = New-CplConfiguration -ProxyPort $Configuration.proxyPort -ProxyHost $Configuration.proxyHost
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Configuration directory does not exist.' }
    $temporary = Join-Path $parent ('.launcher-config-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($validated | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($full)) { [IO.File]::Replace($temporary, $full, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $full) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Resolve-CplExecutable {
    param([Parameter(Mandatory = $true)][string]$InstallLocation, [Parameter(Mandatory = $true)][string]$RelativeExecutable)
    $root = [IO.Path]::GetFullPath($InstallLocation).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ([IO.Path]::IsPathRooted($RelativeExecutable)) { throw 'Package executable must be relative to its registered package directory.' }
    $executable = [IO.Path]::GetFullPath((Join-Path $root $RelativeExecutable))
    if (-not $executable.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($executable) -ine '.exe') {
        throw 'Invalid package executable path.'
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Registered package executable does not exist.' }
    return $executable
}

function Get-CplPackage {
    if ($null -eq (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        throw 'Get-AppxPackage is unavailable. Use Windows PowerShell 5.1, not a WSL/Linux shell.'
    }
    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if ($null -eq $package) { throw 'Microsoft Store package OpenAI.Codex is not registered for this Windows user.' }
    if ($package.PackageFamilyName -ne 'OpenAI.Codex_2p2nqsd0c76g0') { throw 'Unexpected package publisher/family. No executable was launched.' }
    [xml]$manifest = Get-Content -LiteralPath (Join-Path $package.InstallLocation 'AppxManifest.xml') -Raw -Encoding UTF8
    $application = $manifest.SelectNodes("//*[local-name()='Applications']/*[local-name()='Application']") | Where-Object { $_.Id -eq 'App' } | Select-Object -First 1
    if ($null -eq $application) { throw 'The registered package has no supported App application entry. Revalidation is required.' }
    $family = $manifest.SelectNodes("//*[local-name()='TargetDeviceFamily']") | Select-Object -First 1
    $executable = Resolve-CplExecutable -InstallLocation $package.InstallLocation -RelativeExecutable $application.Executable
    return [pscustomobject][ordered]@{
        Name = $package.Name; Family = $package.PackageFamilyName; Version = [string]$package.Version
        Architecture = [string]$package.Architecture; InstallLocation = $package.InstallLocation
        Executable = $executable; MinimumWindowsVersion = [string]$family.MinVersion
    }
}

function Get-CplRunningClients {
    $clients = @()
    foreach ($process in @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $process.Path } catch { }
        if ([string]::IsNullOrWhiteSpace($path)) {
            $clients += [pscustomobject]@{ Pid = $process.Id; PackageVersion = 'Unknown'; Identification = 'Unknown'; Path = $null }
        } elseif ($path -match '(?i)[\\/]OpenAI\.Codex_([^\\/]+)[\\/]app[\\/]ChatGPT\.exe$') {
            $clients += [pscustomobject]@{ Pid = $process.Id; PackageVersion = $Matches[1]; Identification = 'OpenAI.Codex'; Path = $path }
        }
    }
    return $clients
}

function Wait-CplTask {
    param([Parameter(Mandatory = $true)]$Task, [int]$TimeoutMs, [string]$Stage)
    if ($TimeoutMs -le 0 -or -not $Task.Wait($TimeoutMs)) { throw [TimeoutException]::new("$Stage timed out.") }
    # Wait propagates task faults. GetResult unwraps successful Task<T> when needed by callers.
}

function Read-CplHttpHeader {
    param([Parameter(Mandatory = $true)]$Stream, [int]$TimeoutMs = 5000)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $builder = [Text.StringBuilder]::new()
    $one = New-Object byte[] 1
    while ($builder.Length -lt 8192) {
        $task = $Stream.ReadAsync($one, 0, 1)
        Wait-CplTask -Task $task -TimeoutMs ([int]($TimeoutMs - $timer.ElapsedMilliseconds)) -Stage 'HTTP header'
        if ($task.Result -eq 0) { throw [IO.IOException]::new('Connection closed before the HTTP header was complete.') }
        [void]$builder.Append([char]$one[0])
        if ($builder.Length -ge 4 -and $builder.ToString($builder.Length - 4, 4) -eq "`r`n`r`n") { return $builder.ToString() }
    }
    throw [IO.InvalidDataException]::new('HTTP header exceeded 8192 bytes.')
}

function Get-CplFailure {
    param([Parameter(Mandatory = $true)]$Exception, [string]$Stage)
    $errorValue = $Exception
    $codes = @()
    while ($null -ne $errorValue.InnerException) {
        $codes += ('{0:X8}' -f ([long]$errorValue.HResult -band 0xffffffffL))
        $errorValue = $errorValue.InnerException
    }
    $codes += ('{0:X8}' -f ([long]$errorValue.HResult -band 0xffffffffL))
    if ($errorValue -is [ComponentModel.Win32Exception]) { $codes += ('{0:X8}' -f ([long]$errorValue.NativeErrorCode -band 0xffffffffL)) }
    $category = $Stage + 'Failure'
    if ($codes -contains '8009030E') { $category = 'LocalTlsCredentialError' }
    elseif ($errorValue -is [TimeoutException]) { $category = $Stage + 'Timeout' }
    return [pscustomobject]@{ Stage = $Stage; Category = $category; Message = $errorValue.Message; Codes = @($codes | Select-Object -Unique) }
}

function Invoke-CplNetworkProbe {
    param([Parameter(Mandatory = $true)]$Configuration, [string]$TargetHost = 'chatgpt.com', [int]$TimeoutMs = 5000)
    $validated = New-CplConfiguration -ProxyPort $Configuration.proxyPort -ProxyHost $Configuration.proxyHost
    if ($TargetHost -notmatch '^[A-Za-z0-9.-]+$') { throw 'Invalid diagnostic target hostname.' }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = [ordered]@{
        Success = $false; ProxyTcp = $false; HttpConnect = $false; Tls = $false; TlsProtocol = $null
        HttpStatus = $null; HttpDisposition = 'NotTested'; ApplicationVerification = 'NotTested'
        Failure = $null; HttpWarning = $null; ElapsedMs = 0
    }
    $client = $null; $tls = $null; $stage = 'ProxyTcp'
    try {
        $client = [Net.Sockets.TcpClient]::new()
        Wait-CplTask -Task ($client.ConnectAsync($validated.proxyHost, $validated.proxyPort)) -TimeoutMs $TimeoutMs -Stage $stage
        $result.ProxyTcp = $true
        $client.SendTimeout = $TimeoutMs
        $client.ReceiveTimeout = $TimeoutMs
        $stage = 'HttpConnect'
        $network = $client.GetStream()
        $bytes = [Text.Encoding]::ASCII.GetBytes("CONNECT ${TargetHost}:443 HTTP/1.1`r`nHost: ${TargetHost}:443`r`n`r`n")
        Wait-CplTask -Task ($network.WriteAsync($bytes, 0, $bytes.Length)) -TimeoutMs $TimeoutMs -Stage $stage
        $header = Read-CplHttpHeader -Stream $network -TimeoutMs $TimeoutMs
        $status = ($header -split "`r`n")[0]
        if ($status -notmatch '^HTTP/1\.[01] 200(?:\s|$)') { throw [IO.IOException]::new("Proxy rejected CONNECT: $status") }
        $result.HttpConnect = $true
        $stage = 'Tls'
        $tls = [Net.Security.SslStream]::new($network, $false)
        Wait-CplTask -Task ($tls.AuthenticateAsClientAsync($TargetHost)) -TimeoutMs $TimeoutMs -Stage $stage
        $result.Tls = $tls.IsAuthenticated
        $result.TlsProtocol = [string]$tls.SslProtocol
        $result.Success = $result.Tls
        $stage = 'Http'
        try {
            $bytes = [Text.Encoding]::ASCII.GetBytes("HEAD / HTTP/1.1`r`nHost: $TargetHost`r`nConnection: close`r`nUser-Agent: CodexProxyLauncher/1.0`r`n`r`n")
            Wait-CplTask -Task ($tls.WriteAsync($bytes, 0, $bytes.Length)) -TimeoutMs $TimeoutMs -Stage $stage
            $header = Read-CplHttpHeader -Stream $tls -TimeoutMs $TimeoutMs
            if (($header -split "`r`n")[0] -notmatch '^HTTP/1\.[01] (\d{3})(?:\s|$)') { throw 'Invalid target HTTP response.' }
            $result.HttpStatus = [int]$Matches[1]
            if ($header -match '(?im)^cf-mitigated:\s*challenge') { $result.HttpDisposition = 'WebChallenge' }
            elseif ($result.HttpStatus -eq 401) { $result.HttpDisposition = 'AuthenticationRequired' }
            elseif ($result.HttpStatus -eq 403) { $result.HttpDisposition = 'HttpForbidden' }
            else { $result.HttpDisposition = 'HttpResponseReceived' }
        } catch {
            $result.HttpDisposition = 'HttpUnverified'
            $result.HttpWarning = Get-CplFailure -Exception $_.Exception -Stage $stage
        }
    } catch {
        $result.Failure = Get-CplFailure -Exception $_.Exception -Stage $stage
    } finally {
        if ($null -ne $tls) { $tls.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        $result.ElapsedMs = $watch.ElapsedMilliseconds
    }
    return [pscustomobject]$result
}

function Get-CplSystemProxyObservation {
    try {
        $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $enabled = $null; $pac = $false
        if ($null -ne $settings.PSObject.Properties['ProxyEnable']) { $enabled = [bool]$settings.ProxyEnable }
        if ($null -ne $settings.PSObject.Properties['AutoConfigURL']) { $pac = -not [string]::IsNullOrWhiteSpace($settings.AutoConfigURL) }
        return [pscustomobject]@{ ManualProxyEnabled = $enabled; PacConfigured = $pac; TunMode = 'NotObserved'; Note = 'Read-only user settings; not proof of effective enterprise/network policy.' }
    } catch { return [pscustomobject]@{ ManualProxyEnabled = $null; PacConfigured = $null; TunMode = 'NotObserved'; Note = 'Could not read user proxy settings.' } }
}

function New-CplProcessStartInfo {
    param([Parameter(Mandatory = $true)]$Package, [Parameter(Mandatory = $true)]$Configuration)
    $validated = New-CplConfiguration -ProxyPort $Configuration.proxyPort -ProxyHost $Configuration.proxyHost
    $uri = [UriBuilder]::new('http', $validated.proxyHost, $validated.proxyPort).Uri.GetLeftPart([UriPartial]::Authority)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Package.Executable
    $info.WorkingDirectory = $Package.InstallLocation
    $info.UseShellExecute = $false
    $info.Arguments = '--proxy-server=' + $uri
    $info.EnvironmentVariables['HTTP_PROXY'] = $uri
    $info.EnvironmentVariables['HTTPS_PROXY'] = $uri
    $info.EnvironmentVariables['NO_PROXY'] = 'localhost,127.0.0.1,::1'
    $info.EnvironmentVariables.Remove('ALL_PROXY')
    # Windows environment names are case-insensitive. Do not create duplicate lowercase aliases.
    # Keep CODEX_HOME, SSL_CERT_FILE and other certificate/runtime settings inherited.
    $windows = [Environment]::GetFolderPath('Windows')
    $defaults = @{
        SystemRoot = $windows; ComSpec = (Join-Path $windows 'System32\cmd.exe')
        USERPROFILE = [Environment]::GetFolderPath('UserProfile')
        APPDATA = [Environment]::GetFolderPath('ApplicationData')
        LOCALAPPDATA = [Environment]::GetFolderPath('LocalApplicationData')
    }
    foreach ($name in $defaults.Keys) {
        if ([string]::IsNullOrWhiteSpace($info.EnvironmentVariables[$name])) { $info.EnvironmentVariables[$name] = $defaults[$name] }
    }
    return $info
}

function Get-CplDiagnostic {
    param([Parameter(Mandatory = $true)]$Configuration)
    $package = $null; $packageError = $null
    try { $package = Get-CplPackage } catch { $packageError = $_.Exception.Message }
    $clients = @(Get-CplRunningClients)
    $network = Invoke-CplNetworkProbe -Configuration $Configuration
    return [pscustomobject][ordered]@{
        LauncherVersion = $script:CplVersion; TimeUtc = [DateTime]::UtcNow.ToString('o')
        WindowsVersion = [Environment]::OSVersion.Version.ToString(); PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Client = $package; ClientDiscoveryError = $packageError; RunningClients = $clients
        Proxy = $Configuration; SystemProxy = (Get-CplSystemProxyObservation); Network = $network
        Success = ($null -ne $package -and $network.Success)
        Notice = 'Success means registered client found and CONNECT/TLS passed. Login, model requests, browser, plugins, remote access and voice remain separate tests. Paths are local information: review before sharing.'
    }
}

function Write-CplLog {
    param([string]$Message)
    $directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexProxyLauncher\logs'
    try {
        [void][IO.Directory]::CreateDirectory($directory)
        $path = Join-Path $directory 'launcher.log'
        if ([IO.File]::Exists($path) -and (Get-Item -LiteralPath $path).Length -gt 1048576) { Move-Item -LiteralPath $path -Destination ($path + '.previous') -Force }
        Add-Content -LiteralPath $path -Value ([DateTime]::UtcNow.ToString('o') + ' ' + $Message) -Encoding UTF8
    } catch { Write-Warning ('Could not write launcher log: ' + $_.Exception.Message) }
}

Export-ModuleMember -Function Assert-CplPort, New-CplConfiguration, Read-CplConfiguration, Write-CplConfiguration, Resolve-CplExecutable, Get-CplPackage, Get-CplRunningClients, Read-CplHttpHeader, Get-CplFailure, Invoke-CplNetworkProbe, Get-CplSystemProxyObservation, New-CplProcessStartInfo, Get-CplDiagnostic, Write-CplLog
