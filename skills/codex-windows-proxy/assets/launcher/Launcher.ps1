#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath, [switch]$Configure, [switch]$CheckOnly)
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $scriptDirectory 'launcher.config.json' }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $scriptDirectory 'Launcher.Core.psm1') -Force -DisableNameChecking

function Show-CplConfiguration {
    param([string]$ExistingPort = '')
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Codex Proxy Launcher - Proxy configuration'
    $form.ClientSize = New-Object Drawing.Size(440, 190)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $label = New-Object Windows.Forms.Label
    $label.Text = "Clash / local HTTP or Mixed proxy (127.0.0.1)`r`nEnter your own port (1-65535). No system proxy is required."
    $label.Location = New-Object Drawing.Point(18, 16)
    $label.Size = New-Object Drawing.Size(405, 48)
    $inputBox = New-Object Windows.Forms.TextBox
    $inputBox.Location = New-Object Drawing.Point(20, 75)
    $inputBox.Size = New-Object Drawing.Size(395, 25)
    $inputBox.Text = $ExistingPort
    $save = New-Object Windows.Forms.Button
    $save.Text = 'Save'
    $save.Location = New-Object Drawing.Point(225, 135)
    $save.DialogResult = [Windows.Forms.DialogResult]::OK
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object Drawing.Point(330, 135)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.AddRange(@($label, $inputBox, $save, $cancel))
    $form.AcceptButton = $save
    $form.CancelButton = $cancel
    try {
        while ($true) {
            if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
            try { return New-CplConfiguration -ProxyPort $inputBox.Text.Trim() }
            catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Invalid port') }
        }
    } finally { $form.Dispose() }
}

try {
    if ($CheckOnly -and $Configure) { throw 'CheckOnly and Configure cannot be combined.' }
    if ($CheckOnly) {
        $configuration = Read-CplConfiguration -Path $ConfigPath
        $diagnostic = Get-CplDiagnostic -Configuration $configuration
        $diagnostic | ConvertTo-Json -Depth 8
        if ($diagnostic.Success) { exit 0 } else { exit 20 }
    }
    $exists = Test-Path -LiteralPath $ConfigPath -PathType Leaf
    if ($Configure -or -not $exists) {
        $oldPort = ''
        if ($exists) {
            try { $oldPort = [string](Read-CplConfiguration -Path $ConfigPath).proxyPort } catch { }
        }
        $configuration = Show-CplConfiguration -ExistingPort $oldPort
        if ($null -eq $configuration) { exit 2 }
        Write-CplConfiguration -Path $ConfigPath -Configuration $configuration
        if ($Configure) { Write-Output 'Configuration saved. Existing Codex processes were not changed.'; exit 0 }
    } else { $configuration = Read-CplConfiguration -Path $ConfigPath }
    $package = Get-CplPackage
    $existing = @(Get-CplRunningClients)
    if ($existing.Count -gt 0) {
        throw 'A Codex/ChatGPT desktop process is already running (possibly an older package version). Save your tasks, fully exit the client yourself, then launch again. This launcher will not kill it.'
    }
    $probe = Invoke-CplNetworkProbe -Configuration $configuration
    if (-not $probe.Success) {
        Add-Type -AssemblyName System.Windows.Forms
        $message = "Preflight did not pass: $($probe.Failure.Category)`r`n$($probe.Failure.Message)`r`n`r`nThis does not prove a Clash node is broken. Local TLS credentials, trust, policy, or the route may be responsible.`r`n`r`nLaunch anyway?"
        if ([Windows.Forms.MessageBox]::Show($message, 'Network preflight incomplete', 'YesNo', 'Warning') -ne [Windows.Forms.DialogResult]::Yes) { exit 21 }
    }
    # Recheck immediately before launch, including old package versions.
    if (@(Get-CplRunningClients).Count -gt 0) { throw 'A desktop client appeared during preflight. Fully exit it before retrying.' }
    $startInfo = New-CplProcessStartInfo -Package $package -Configuration $configuration
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'Windows did not create a client process.' }
    try {
        $pidValue = $process.Id
        if ($process.WaitForExit(1500)) { throw "Client process exited immediately (exit code $($process.ExitCode)); no window/login success is claimed." }
        Write-CplLog -Message "START package=$($package.Version) pid=$pidValue connectTls=$($probe.Success) applicationVerification=Pending"
        Write-Output "Client process created: $pidValue. Verify the visible window, account and an actual task separately."
    } finally { $process.Dispose() }
    exit 0
} catch {
    if ($CheckOnly) {
        [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; ApplicationVerification = 'NotTested' } | ConvertTo-Json -Depth 4
        exit 20
    }
    Write-CplLog -Message ('ERROR ' + $_.Exception.Message)
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex Proxy Launcher', 'OK', 'Warning')
    exit 20
}
