---
name: codex-windows-proxy
description: Install, configure, inspect, or uninstall a per-process proxy launcher for the Windows Microsoft Store OpenAI.Codex desktop client. Use for running this client through a local Clash HTTP/Mixed port without enabling Windows system proxy or TUN. Does not provide VPN service, install Clash, or configure macOS, Linux, WSL, or arbitrary applications.
---

# Codex Windows Proxy

Use the bundled launcher payload. Read [the compatibility and acceptance guide](references/verification.md) before claiming a feature or client version works. All new-version desktop acceptance is initially pending; `-CheckOnly` is a transport check.

## Install or change the port

1. Confirm this is Windows with the Microsoft Store package `OpenAI.Codex`. Run package discovery using Windows PowerShell 5.1 if the current shell cannot load `Get-AppxPackage`.
2. Obtain the actual HTTP/Mixed port from the human user. Do not assume 7897, scan common ports, or silently reuse `.codex/.env`. If it has not been supplied, ask. The proxy service must already be running locally.
3. Run `scripts/Install-Launcher.ps1 -ProxyPort <user-provided-port>` with Windows PowerShell 5.1. It installs only this launcher's files under the current user's local application data and creates a separately named desktop shortcut. Existing Codex shortcuts, account data, system proxy, TUN, startup tasks, and `config.toml` stay untouched.
4. Run the installed `Launcher.ps1 -CheckOnly` with Windows PowerShell 5.1 and examine the JSON and exit code. A copied package is not evidence of connectivity or client readiness.

Use the Windows directory resolved from the operating system, not a literal drive letter or another user's cached runtime. The interpreter is `System32/WindowsPowerShell/v1.0/powershell.exe` beneath that directory. Invoke scripts with `-NoProfile -STA -ExecutionPolicy Bypass -File`. Bypass applies to this process and does not override enforced organization policy; do not change machine execution policy to work around a block.

## Launch and verify

Ask the user to save ongoing tasks and fully exit the desktop client at their chosen time. Never kill an existing desktop session merely to apply proxy settings. After exit, they can use the new shortcut or installed `.cmd` entry.

The core supplies Chromium's explicit proxy switch and child-process HTTP/HTTPS proxy variables. It keeps local loopback traffic direct. Do not add `--proxy-bypass-list=<-loopback>` as a supposed localhost exemption: it removes the implicit exemption.

Check visible window, account loading, an actual model turn, and the needed tools separately. Browser, plugins, remote control, voice, image generation and external tool programs need their own acceptance records. Never label all features verified from a TCP connection, TLS handshake, process creation, or a previous client version.

For the no-global-proxy scenario, record the user's actual system proxy and TUN state. Do not toggle them without authorization or interrupt unrelated connections. If their state cannot be observed, mark it unknown rather than claiming the acceptance environment was satisfied.

## Diagnose and remove

- `scripts/Check-Launcher.ps1` is read-only: no dialog, config edit, client launch, or log write. Nonzero exit means client discovery or transport did not pass. HTTP 403/challenge after valid TLS is not proof of a broken tunnel and not proof of login success.
- `LocalTlsCredentialError` indicates the detector's local Schannel environment. Retry the same read-only check in ordinary Windows PowerShell outside a restricted executor before blaming the route. Never disable certificate verification.
- Use the installed `Configure Proxy.cmd` or edit its `launcher.config.json`; changing a file does not reconfigure an already-running client.
- `scripts/Uninstall-Launcher.ps1` removes only owned launcher files and its identifiable shortcut. Configuration is kept by default; `-RemoveConfiguration` removes that too. Never delete `.codex`, application packages, proxy software, credentials, or unrelated files.

Bundled payload provenance and SHA-256 values are in `assets/launcher/UPSTREAM.json`. Do not modify the runtime to work around a failure without updating tests and recording the exact version and validation status.
