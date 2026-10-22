# Codex Windows Proxy Skill

�� Windows �̵�� Codex ��Ӧ�ü���������������ɿɰ�װ���ɼ�顢��ж�ص� skill��**��װʱ�������û��ṩ���� HTTP/Mixed �����˿�**�����²�˿ڣ�������ϵͳ������ TUN��

��ǰ�汾��`1.0.0-rc.1`���ͻ���������������������֤�д��������¡��������Ƽ����� EXE �� [�������ֿ�](https://github.com/LiKa233/codex-windows-proxy-launcher)�����Ƿ�Χ�� [��ָ֤��](skills/codex-windows-proxy/references/verification.md)��

English: A Codex skill for installing and inspecting the per-process Windows Microsoft Store client launcher. The user must provide their actual local HTTP/Mixed proxy port. The launcher scripts are bundled with SHA-256 provenance, so installation does not fetch an unpinned runtime. This is a release candidate, not a claim of full client feature compatibility.

## ���û����Ͱ汾

- Windows x64��Windows PowerShell 5.1����ǰ�û���װ���̵�� `OpenAI.Codex_2p2nqsd0c76g0`��
- ��ǰ�����۲쵽�Ѱ�װ MSIX `26.1013.4894.0`���������оɰ� `26.1007.9446.0`��ǰ��������/���������Դ���֤��
- ��ǰ��������Ϊ Windows 11 `10.0.26100`���嵥���Ҫ��Ϊ `10.0.19041.0`�����ܰ��������ż�д�� Windows 10 ��ʵ�⡣
- ��������������֤�� HTTP/Mixed ������SOCKS-only��Զ�̴�����macOS/Linux/WSL �ڿͻ��˲����װ淶Χ��
- skill ������Ҫ�� .NET EXE��Node.js��Python ����� CLI���䰲װ/�������� Windows PowerShell�������Լ��� skill ��װ��ʽ��������Ҫ��

## ��װ skill

��֧�ֱ��� skills �� Codex ��˵����

> �밲װ GitHub �ֿ� `LiKa233/codex-windows-proxy-skill` �е� `skills/codex-windows-proxy`��

Ҳ�����زֿ⣬������ `skills/codex-windows-proxy` �ļ��зŵ���ǰ����֧�ֵĸ��� skills Ŀ¼����ǰ�ٷ��ĵ��г��ĸ���Ŀ¼Ϊ `~/.agents/skills`��ĳЩ�ɰ�ͻ���/��װ����ʹ�� `~/.codex/skills`����������ʵ�ʷ�����ΪΪ׼���ֿ⼶λ��Ϊ `.agents/skills`�����¼���/����������ȷ���ܷ��� `$codex-windows-proxy`�������ļ��������������������װ���������ա�

����ʾ����

> ʹ�� `$codex-windows-proxy` ��װ����������������ȷ�� HTTP/Mixed �˿ڣ�������ǰ�ͻ��˺����ڽ��е�����

## �ֶ���װ������

���� `skills/codex-windows-proxy` Ŀ¼���� Windows PowerShell 5.1 ��ִ�У�

```powershell
$myProxyPort = Read-Host '���������Լ��� HTTP/Mixed �����˿�'
.\scripts\Install-Launcher.ps1 -ProxyPort $myProxyPort
```

δ����˿�ʱ����װ�ű�Ҳ��Ҫ�����롣ȱʧ�������ֻ��� `1�C65535` ��ֵ���ᱻ�滻ΪĬ��ֵ��

Ĭ�ϰ�װĿ¼��`%LOCALAPPDATA%\CodexProxyLauncher\installed`�����������ݷ�ʽ `Codex Proxy Launcher.lnk`��������ԭ������������ͬ�����޷�ȷ�����ڱ���װ�Ŀ�ݷ�ʽ��ֹͣ��װ��˵��ԭ��

��װֻ�����������ļ������ã��������ɿͻ��ˡ����޸� `.codex/config.toml`���˻���ϵͳ������TUN �����������񡣰�װ�����ȷ���֡��ļ��Ѱ�װ���͡���������֤����

## �����ʹ��

```powershell
.\scripts\Check-Launcher.ps1
```

���ʹ�� Windows PowerShell 5.1������ֲ� JSON ���˳��룬���������������ͻ��ˡ���д���û���־��`Success` ����ʾ���ֿͻ����� CONNECT/TLS ͨ����403/��ҳ��֤���˺ż�����״̬�ֱ��¼��

��������������ȫ�˳�����ͻ��˺�ʹ���¿�ݷ�ʽ���������ɰ��������У�����������ֹ���þ�ʵ����˵��ԭ�򣬲��Զ���ֹ����

�˿ڱ仯�󣬿ɱ༭��װĿ¼�е� `launcher.config.json`��˫�� `Configure Proxy.cmd`�����ٴδ��¶˿����а�װ�ű������ñ仯ֻ���´��½�������ʱӦ�á�

## ԭ����߽�

�������ĸ� Chromium ������ʽ `--proxy-server`����֧�ֻ����������ӽ��̴��� `HTTP_PROXY/HTTPS_PROXY`������ֻ�����ڸý��������ػ���ַ����ֱ����Clash ����λ�� `127.0.0.1` ����������������

�����߲������ `--proxy-bypass-list=<-loopback>`�������������˼��**ȡ��** Chromium ����ʽ�����ƹ��������ñ��ص�ֱַ����

�����˿ڴ����� HTTP �������ã�CONNECT �ɹ������� TLS �ɹ���TLS �ɹ��������˻����Ի������й��߿��á�������������Զ�����ӡ���������������ջ����ֱ���֤������Ҫ��ȷ��ϵͳ�����رա�TUN �رա�������������

���ݣ�[Electron ����](https://www.electronjs.org/docs/latest/api/command-line-switches)��[Chromium ��������](https://chromium.googlesource.com/chromium/src/+/HEAD/net/docs/proxy.md)��[OpenAI skills �ĵ�](https://developers.openai.com/codex/skills)������˵�������ʵ�⡣

## ж����ά��

```powershell
.\scripts\Uninstall-Launcher.ps1
# ��ҲҪɾ���������Լ��Ķ˿����ã�
.\scripts\Uninstall-Launcher.ps1 -RemoveConfiguration
```

ж�ؽű���������Ȩ��Ǻ͹̶��ļ����Ƴ��ļ������ݹ�ɾ����װĿ¼������·����Ĭ�ϱ����˿����ú�����Ȩ��ǣ���ʹĿ¼���������ŵ��ļ���Ҳ�ᱣ����������ָ�򱾰�װʱ��ɾ����ݷ�ʽ��

skill ������ͨ�������� skills ���������Ƴ�����ɾ���㸴�Ƶ� skill �ļ��У�����ж���Ѱ�װ���������������¡�

����Դ��Ϊ�����������ֿ�� `src`�����հ汾��ÿ���ļ��� SHA-256 ��¼�� `assets/launcher/UPSTREAM.json`����װǰ���У�顣У��ֵ˵������һ���ԣ����Ƿ����ߵ�����ǩ����

���Ժͷ��а��� Windows CI �����ɣ��� Actions �� Releases�����մ������ĵ����£���ǰ��δ֤�����пͻ��˹����ڹر�ϵͳ����/TUN ʱ�����á�

����֤��MIT���� [LICENSE](LICENSE)��
