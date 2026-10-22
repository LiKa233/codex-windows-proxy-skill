# Codex Windows Proxy Skill

将 Windows 商店版 Codex 的应用级代理启动器打包成可安装、可检查、可卸载的 skill。**安装时必须由用户提供本机 HTTP/Mixed 代理端口**，不猜测端口，不开启系统代理或 TUN。

当前版本：`1.0.0-rc.1`。客户端冷启动和完整功能验证尚待后续更新。完整机制及独立 EXE 见 [启动器仓库](https://github.com/LiKa233/codex-windows-proxy-launcher)，覆盖范围见 [验证指南](skills/codex-windows-proxy/references/verification.md)。

English: A Codex skill for installing and inspecting the per-process Windows Microsoft Store client launcher. The user must provide their actual local HTTP/Mixed proxy port. The launcher scripts are bundled with SHA-256 provenance, so installation does not fetch an unpinned runtime. This is a release candidate, not a claim of full client feature compatibility.

## 适用环境和版本

- Windows x64、Windows PowerShell 5.1；当前用户安装了商店包 `OpenAI.Codex_2p2nqsd0c76g0`。
- 当前机器观察到已安装 MSIX `26.1013.4894.0`，但仍运行旧版 `26.1007.9446.0`。前者冷启动/功能验收仍待验证。
- 当前开发环境为 Windows 11 `10.0.26100`。清单最低要求为 `10.0.19041.0`，不能把这个最低门槛写成 Windows 10 已实测。
- 本机已有无需认证的 HTTP/Mixed 代理；SOCKS-only、远程代理、macOS/Linux/WSL 内客户端不是首版范围。
- skill 自身不要求 .NET EXE、Node.js、Python 或独立 CLI；其安装/运行依靠 Windows PowerShell。宿主自己的 skill 安装方式可能另有要求。

## 安装 skill

在支持本地 skills 的 Codex 中说明：

> 请安装 GitHub 仓库 `LiKa233/codex-windows-proxy-skill` 中的 `skills/codex-windows-proxy`。

也可下载仓库，将整个 `skills/codex-windows-proxy` 文件夹放到当前宿主支持的个人 skills 目录。当前官方文档列出的个人目录为 `~/.agents/skills`；某些旧版客户端/安装器仍使用 `~/.codex/skills`，须以宿主实际发现行为为准。仓库级位置为 `.agents/skills`。重新加载/重启宿主后确认能发现 `$codex-windows-proxy`。复制文件不等于已完成启动器安装或联网验收。

调用示例：

> 使用 `$codex-windows-proxy` 安装启动器。请先向我确认 HTTP/Mixed 端口，保留当前客户端和正在进行的任务。

## 手动安装启动器

进入 `skills/codex-windows-proxy` 目录，在 Windows PowerShell 5.1 中执行：

```powershell
$myProxyPort = Read-Host '请输入你自己的 HTTP/Mixed 代理端口'
.\scripts\Install-Launcher.ps1 -ProxyPort $myProxyPort
```

未传入端口时，安装脚本也会要求输入。缺失、非数字或不在 `1–65535` 的值不会被替换为默认值。

默认安装目录：`%LOCALAPPDATA%\CodexProxyLauncher\installed`。新增桌面快捷方式 `Codex Proxy Launcher.lnk`，不覆盖原启动器。已有同名但无法确认属于本安装的快捷方式会停止安装并说明原因。

安装只放置启动器文件和配置，不结束旧客户端、不修改 `.codex/config.toml`、账户、系统代理、TUN 或自启动任务。安装结果明确区分“文件已安装”和“连接已验证”。

## 检查与使用

```powershell
.\scripts\Check-Launcher.ps1
```

检查使用 Windows PowerShell 5.1，输出分层 JSON 和退出码，不弹窗、不启动客户端、不写配置或日志。`Success` 仅表示发现客户端且 CONNECT/TLS 通过；403/网页验证、账号及功能状态分别记录。

保存任务并自行完全退出桌面客户端后，使用新快捷方式启动。若旧版仍在运行，启动器会阻止复用旧实例并说明原因，不自动终止任务。

端口变化后，可编辑安装目录中的 `launcher.config.json`，双击 `Configure Proxy.cmd`，或再次带新端口运行安装脚本。配置变化只在下次新进程启动时应用。

## 原理与边界

启动核心给 Chromium 传递显式 `--proxy-server`，给支持环境变量的子进程传递 `HTTP_PROXY/HTTPS_PROXY`；设置只作用于该进程树。回环地址保持直连，Clash 自身位于 `127.0.0.1` 不妨碍外网代理。

本工具不会加入 `--proxy-bypass-list=<-loopback>`：这个参数的意思是**取消** Chromium 的隐式本地绕过，不是让本地地址直连。

代理端口存活不等于 HTTP 代理可用；CONNECT 成功不等于 TLS 成功；TLS 成功不等于账户、对话和所有工具可用。浏览器、插件、远程连接、语音和其他网络栈必须分别验证，尤其要明确“系统代理关闭、TUN 关闭”的验收条件。

依据：[Electron 参数](https://www.electronjs.org/docs/latest/api/command-line-switches)、[Chromium 代理机制](https://chromium.googlesource.com/chromium/src/+/HEAD/net/docs/proxy.md)、[OpenAI skills 文档](https://developers.openai.com/codex/skills)。机制说明不替代实测。

## 卸载与维护

```powershell
.\scripts\Uninstall-Launcher.ps1
# 如也要删除启动器自己的端口配置：
.\scripts\Uninstall-Launcher.ps1 -RemoveConfiguration
```

卸载脚本根据所有权标记和固定文件名移除文件，不递归删除安装目录或其他路径。默认保留端口配置和所有权标记；即使目录中有你另放的文件，也会保留。仅当仍指向本安装时才删除快捷方式。

skill 本身可通过宿主的 skills 管理功能移除，或删除你复制的 skill 文件夹；这与卸载已安装的启动器是两件事。

上游源码为独立启动器仓库的 `src`。快照版本和每个文件的 SHA-256 记录在 `assets/launcher/UPSTREAM.json`；安装前逐个校验。校验值说明快照一致性，不是发行者的数字签名。

`.gitattributes` 保留文件原始字节，防止 Windows Git 的自动换行转换破坏快照哈希。维护者更改脚本或编码后必须重新导出快照及哈希，不能只更新说明文字。

测试和发行包在 Windows CI 中生成，见 Actions 与 Releases。验收待办随文档更新；当前尚未证明所有客户端功能在关闭系统代理/TUN 时都可用。

许可证：MIT，见 [LICENSE](LICENSE)。
