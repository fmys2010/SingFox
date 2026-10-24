# SingFox

基于 [sing-box](https://github.com/SagerNet/sing-box) 的桌面客户端，Flutter 编写，目前支持 Windows。
内核使用带 XHTTP 与 VLESS Encryption 的分支 [singbox-x](https://github.com/fmys2010/singbox-x)。

## 功能

- 云端订阅、本地配置、本地文件三种配置；内置 VS Code 风格编辑器，按 sing-box schema 补全
- 节点分组、延迟测试（可选统一延迟，去掉握手耗时），节点卡片显示 Reality / XHTTP 等特性
- 规则页与规则集市场（MetaCubeX/meta-rules-dat）
- Redir-Host DNS 覆写：境外与未知域名只经代理查询，不发往本地 DNS
- 出口 IP 与风险评分（IPPure）、网站测速
- 系统代理与代理守卫、TUN（可安装 SingFox 服务，免管理员开启）
- 开机自启（计划任务 / 启动项 / 服务）、静默启动、托盘

## 构建

```powershell
# 内核与 TUN 服务（需要 Go 与 singbox-x 源码）
tools/build_core.ps1 -Source "path\to\singbox-x"
flutter build windows --release
# 安装包（需要 Inno Setup 6）
iscc tools/installer.iss
```
