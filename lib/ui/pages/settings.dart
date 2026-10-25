import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/autostart.dart';
import '../../core/helper_service.dart';
import '../../core/paths.dart';
import '../../core/updater.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../dialogs/dns_servers_dialog.dart';
import '../widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // SINGFOX_SECTION opens a section on launch for scripted checks.
  int _sec = int.tryParse(Platform.environment['SINGFOX_SECTION'] ?? '') ?? 0;
  late final _port = TextEditingController(text: '${AppState.I.settings.mixedPort}');
  late final _delayUrl = TextEditingController(text: AppState.I.settings.delayUrl);

  static const _secs = ['常规', '网络', '内核', '关于'];

  /// Whether singfox-service answers; null while checking.
  bool? _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkService();
  }

  Future<void> _checkService() async {
    final ok = await HelperService.I.available();
    if (mounted) setState(() => _service = ok);
  }

  /// Runs an action that may raise a UAC prompt, showing its error if any.
  Future<void> _elevated(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    final err = await action();
    await _checkService();
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, err ?? done, error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PageHeader('设置'),
        const SizedBox(height: 20),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 168,
              child: Column(children: [
                for (var i = 0; i < _secs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Tap(
                      onTap: () => setState(() => _sec = i),
                      child: AnimatedContainer(
                        duration: SF.fast,
                        curve: Curves.easeOut,
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(color: i == _sec ? SF.raised : SF.raised.withValues(alpha: 0), borderRadius: BorderRadius.circular(8)),
                        child: AnimatedDefaultTextStyle(
                          duration: SF.fast,
                          style: SF.t(13, color: i == _sec ? SF.text : SF.text3, weight: FontWeight.w500),
                          child: Text(_secs[i]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: FadeSlideSwitcher(
                    child: ListView(
                      key: ValueKey(_sec),
                      children: switch (_sec) { 0 => [..._startup(), ..._general()], 1 => [..._inbound(), ..._dns()], 2 => _core(), _ => _about() },
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _label(String t, {bool first = false}) => Padding(
        padding: EdgeInsets.only(left: 2, bottom: 10, top: first ? 0 : 24),
        child: Text(t, style: SF.t(12, color: SF.text3)),
      );

  Widget _group(List<Widget> rows) => SFCard(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: SF.lineInner))),
              child: rows[i],
            ),
        ]),
      );

  Widget _row(String title, String sub, Widget control) => SizedBox(
        height: 62,
        child: Row(children: [
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: SF.t(13.5, weight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(sub, style: SF.t(12, color: SF.text3), overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 16),
          control,
        ]),
      );

  List<Widget> _general() {
    final s = AppState.I;
    return [
      _label('日志'),
      _group([
        _row('日志级别', '内核输出的最低级别，修改后重启内核生效', Segmented<String>(
          options: const [('debug', 'debug'), ('info', 'info'), ('warn', 'warn'), ('error', 'error')],
          value: s.settings.logLevel,
          mono: true,
          dense: true,
          background: SF.bg,
          onChanged: (v) => s.updateSettings((x) => x.logLevel = v).then((_) => setState(() {})),
        )),
      ]),
      _label('延迟测试'),
      _group([
        _row('测试地址', '节点测速请求的 URL', SFInput(
          controller: _delayUrl,
          width: 300,
          mono: true,
          background: SF.bg,
          onSubmitted: (v) => s.updateSettings((x) => x.delayUrl = v.trim(), restart: false),
        )),
        _row('统一延迟', '只计第二次请求的耗时，去掉 TCP、TLS 与代理握手，结果更接近实际使用', SFSwitch(
          value: s.settings.unifiedDelay,
          onChanged: (v) => s.updateSettings((x) => x.unifiedDelay = v, restart: false).then((_) => setState(() {})),
        )),
      ]),
    ];
  }

  List<Widget> _inbound() {
    final s = AppState.I;
    final st = s.settings;
    return [
      _label('入站', first: true),
      _group([
        _row('混合端口', 'HTTP 与 SOCKS5 共用的本地监听端口，回车保存', SFInput(
          controller: _port,
          width: 96,
          mono: true,
          background: SF.bg,
          textAlign: TextAlign.right,
          onSubmitted: (v) {
            final p = int.tryParse(v);
            if (p == null || p < 1 || p > 65535) return toast(context, '端口无效', error: true);
            s.updateSettings((x) => x.mixedPort = p);
          },
        )),
        _row('系统代理', '连接时把 Windows 系统代理指向混合端口，切换无需重启内核', SFSwitch(value: st.systemProxy, onChanged: (v) => s.setSystemProxy(v).then((_) => setState(() {})))),
        _row('代理守卫', st.systemProxy ? '每 ${st.proxyGuardSeconds} 秒检查一次，系统代理被其他程序改掉时自动恢复' : '需要先开启系统代理', Row(children: [
          if (st.systemProxy && st.proxyGuard) ...[
            Segmented<int>(
              options: const [(3, '3s'), (5, '5s'), (15, '15s'), (30, '30s')],
              value: st.proxyGuardSeconds,
              mono: true,
              dense: true,
              background: SF.bg,
              onChanged: (v) => s.updateSettings((x) => x.proxyGuardSeconds = v, restart: false).then((_) => s.setProxyGuard(true)).then((_) => setState(() {})),
            ),
            const SizedBox(width: 12),
          ],
          SFSwitch(value: st.proxyGuard && st.systemProxy, onChanged: st.systemProxy ? (v) => s.setProxyGuard(v).then((_) => setState(() {})) : null),
        ])),
        _row('允许局域网连接', '监听 ::，其他设备可使用本机代理', SFSwitch(value: st.allowLan, onChanged: (v) => s.updateSettings((x) => x.allowLan = v))),
      ]),
      _label('TUN'),
      _group([
        _row(
          '启用 TUN',
          PlatformHelper.isAdmin()
              ? '创建虚拟网卡接管系统流量'
              : _service == true
                  ? '通过 SingFox 服务运行，无需管理员权限'
                  : '需要管理员权限，或先安装下方的 SingFox 服务',
          Row(children: [
            if (!PlatformHelper.isAdmin() && _service != true && Platform.isWindows) ...[
              SFButton('以管理员重启', height: 30, onTap: () async {
                await s.shutdown();
                await PlatformHelper.relaunchAsAdmin();
              }),
              const SizedBox(width: 12),
            ],
            SFSwitch(value: st.tun, onChanged: (v) => s.updateSettings((x) => x.tun = v)),
          ]),
        ),
        _row('协议栈', '推荐 auto（sing-tun 自带协议栈）；遇到兼容问题时切换', Segmented<String>(
          options: const [('auto', 'auto'), ('mixed', 'mixed'), ('system', 'system'), ('gvisor', 'gvisor')],
          value: st.tunStack,
          mono: true,
          dense: true,
          background: SF.bg,
          onChanged: (v) => s.updateSettings((x) => x.tunStack = v),
        )),
        _row('严格路由', '阻止经其他网卡发出的 DNS 与 IPv6 流量，防止绕过 TUN 泄漏', SFSwitch(value: st.strictRoute, onChanged: (v) => s.updateSettings((x) => x.strictRoute = v))),
        if (Platform.isWindows)
          _row(
            'SingFox 服务',
            switch (_service) {
              null => '正在检查…',
              true => '已安装 · 以系统服务运行内核，普通权限即可开启 TUN',
              false => '安装后无需管理员身份即可开启 TUN（安装时需授权一次）',
            },
            Row(children: [
              if (_service == true) ...[
                SFButton('更新内核', height: 30, onTap: _busy || s.coreBinary == null ? null : () => _elevated(() => HelperService.I.install(s.coreBinary!), '服务内核已更新')),
                const SizedBox(width: 8),
                SFButton('卸载', kind: BtnKind.danger, height: 30, onTap: _busy || s.coreBinary == null ? null : () async {
                  if (s.running && s.settings.tun && !PlatformHelper.isAdmin()) await s.stop();
                  await _elevated(() => HelperService.I.uninstall(s.coreBinary!), '服务已卸载');
                }),
              ] else
                SFButton('安装服务', kind: BtnKind.primary, height: 30, onTap: _busy || _service == null || s.coreBinary == null ? null : () => _elevated(() => HelperService.I.install(s.coreBinary!), '服务已安装')),
            ]),
          ),
      ]),
    ];
  }

  List<Widget> _startup() {
    final s = AppState.I;
    final st = s.settings;
    return [
      _label('开机自启', first: true),
      _group([
        _row(
          '自启方式',
          switch (st.autostart) {
            'task' => '计划任务：登录后以最高权限启动，TUN 可直接使用',
            'registry' => '系统设置：写入当前用户的启动项，可在任务管理器中管理',
            'service' => '服务：开机即由 SingFox 服务启动内核，无需登录；界面不自动打开',
            _ => '不随系统启动',
          },
          Segmented<String>(
            options: const [('off', '关闭'), ('task', '计划任务'), ('registry', '系统设置'), ('service', '服务')],
            value: st.autostart,
            dense: true,
            background: SF.bg,
            onChanged: _busy
                ? (_) {}
                : (v) async {
                    if (v == 'service' && _service != true) return toast(context, '请先在 网络 → TUN 中安装 SingFox 服务', error: true);
                    setState(() => _busy = true);
                    final err = await Autostart.apply(v);
                    if (err == null) await s.updateSettings((x) => x.autostart = v, restart: false);
                    if (!mounted) return;
                    setState(() => _busy = false);
                    if (err != null) toast(context, err, error: true);
                  },
          ),
        ),
        _row('静默启动', st.showTray ? '开机自启时不弹出窗口，只在托盘运行' : '需要先开启托盘图标', SFSwitch(
          value: st.silentStart && st.showTray,
          onChanged: st.showTray ? (v) => s.updateSettings((x) => x.silentStart = v, restart: false).then((_) => setState(() {})) : null,
        )),
        _row('启动后自动连接', '打开 SingFox 后自动启动内核', SFSwitch(
          value: st.autoConnect,
          onChanged: (v) => s.updateSettings((x) => x.autoConnect = v, restart: false).then((_) => setState(() {})),
        )),
      ]),
      _label('托盘'),
      _group([
        _row('显示托盘图标', '在通知区域显示图标，右键可切换连接、模式与代理', SFSwitch(
          value: st.showTray,
          onChanged: (v) => s.updateSettings((x) => x.showTray = v, restart: false).then((_) => setState(() {})),
        )),
        _row('关闭时最小化到托盘', st.showTray ? '点击关闭按钮只隐藏窗口，内核继续运行；从托盘菜单退出' : '需要先开启托盘图标', SFSwitch(
          value: st.closeToTray && st.showTray,
          onChanged: st.showTray ? (v) => s.updateSettings((x) => x.closeToTray = v, restart: false).then((_) => setState(() {})) : null,
        )),
      ]),
    ];
  }

  List<Widget> _dns() {
    final s = AppState.I;
    final st = s.settings;
    final ours = st.dnsMode == 'redirhost';
    Widget servers(String title, String sub, String hint, List<String> list, void Function(Settings x, List<String> v) set) => _row(
          title,
          '$sub · ${list.length > 1 ? '${list.first} 等 ${list.length} 个' : list.first}',
          SFIconButton(Icons.edit_outlined, tooltip: '编辑服务器', onTap: () async {
            final v = await editDnsServers(context, title: title, hint: hint, servers: list);
            if (v != null) await s.updateSettings((x) => set(x, v));
            setState(() {});
          }),
        );
    return [
      _label('DNS 覆写'),
      _group([
        _row('模式', ours ? '返回真实 IP；未知域名只经代理查询，境外域名不会发往本地 DNS' : '使用配置文件自带的 dns 设置', Segmented<String>(
          options: const [('redirhost', 'Redir-Host 预设'), ('profile', '遵循配置')],
          value: st.dnsMode,
          dense: true,
          background: SF.bg,
          onChanged: (v) => s.updateSettings((x) => x.dnsMode = v).then((_) => setState(() {})),
        )),
        if (ours) ...[
          servers('本地 DNS', '国内与局域网域名，直连', '国内与局域网域名使用，多个服务器并行查询、取最快结果。第一个服务器同时用于解析节点域名。', st.dnsLocal,
              (x, v) => x.dnsLocal = v),
          servers('远程 DNS', '境外与未知域名，经代理', '境外与未知域名使用，经当前代理查询，多个服务器并行查询、取最快结果。', st.dnsRemote, (x, v) => x.dnsRemote = v),
        ],
      ]),
    ];
  }

  List<Widget> _core() {
    final s = AppState.I;
    return [
      _label('内核', first: true),
      _group([
        _row(
          'sing-box ${s.coreVersion.isEmpty ? '' : s.coreVersion}',
          s.coreBinary ?? '未找到内核',
          Row(children: [
            SFButton('选择内核…', height: 30, onTap: () async {
              final r = await FilePicker.platform.pickFiles(dialogTitle: '选择 sing-box 可执行文件', type: FileType.custom, allowedExtensions: ['exe']);
              final p = r?.files.single.path;
              if (p != null) await s.setCorePath(p);
              setState(() {});
            }),
            if (s.settings.corePath.isNotEmpty) ...[
              const SizedBox(width: 8),
              SFButton('恢复默认', height: 30, onTap: () async {
                await s.setCorePath('');
                setState(() {});
              }),
            ],
          ]),
        ),
        _row('更新', '从 GitHub 发布页检查内核新版本（${Updater.coreRepo}）', SFButton(_coreProgress != null ? '下载中 $_coreProgress%' : (_checking == 'core' ? '检查中…' : '检查内核更新'), height: 30, onTap: _checking != null || _coreProgress != null ? null : () => _checkUpdate(core: true))),
        _row('运行状态', s.running ? '运行中 · 控制接口 127.0.0.1:${s.settings.apiPort}' : '未运行', Row(children: [
          SFButton('重启内核', height: 30, onTap: s.running ? s.restart : null),
          const SizedBox(width: 8),
          SFButton('打开数据目录', height: 30, onTap: () => Process.run('explorer', [Paths.I.data.path])),
        ])),
      ]),
    ];
  }

  List<Widget> _about() {
    final s = AppState.I;
    Widget version(String v, String which) => Row(children: [
          Text(v, style: SF.m(12.5, color: SF.text2)),
          const SizedBox(width: 14),
          SFButton(_checking == which ? '检查中…' : '检查更新', height: 30, onTap: _checking != null ? null : () => _checkUpdate(core: which == 'core')),
        ]);
    return [
      _label('关于', first: true),
      _group([
        _row('SingFox', '基于 sing-box 的桌面客户端 · Flutter', version(Updater.appVersion, 'app')),
        _row('内核', '带 XHTTP 与 VLESS Encryption 的 sing-box 分支${s.coreRevision.isEmpty ? '' : ' · ${s.coreRevision.substring(0, min(7, s.coreRevision.length))}'}', version(s.coreVersion, 'core')),
      ]),
    ];
  }

  /// Which update check is running: 'app', 'core' or null.
  String? _checking;

  /// Percent of the core download in progress, null when idle.
  int? _coreProgress;

  Future<void> _installCore(UpdateInfo info) async {
    final s = AppState.I;
    setState(() => _coreProgress = 0);
    try {
      final dir = Directory('${Paths.I.data.path}${Platform.pathSeparator}core');
      final f = await Updater.downloadCore(info, dir,
          proxyPort: s.running ? s.settings.mixedPort : null, onProgress: (p) => mounted ? setState(() => _coreProgress = (p * 100).round()) : null);
      await s.setCorePath(f.path);
      // Drop older downloads; the one in use is the new file.
      for (final e in dir.listSync()) {
        if (e is File && e.path != f.path && e.path.endsWith('.exe')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
      if (s.running) await s.restart();
      if (mounted) toast(context, '内核已更新到 ${info.tag}。服务里的内核需在 TUN 设置中点“更新内核”同步');
    } catch (e) {
      if (mounted) toast(context, '内核更新失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _coreProgress = null);
    }
  }

  Future<void> _checkUpdate({required bool core}) async {
    final s = AppState.I;
    setState(() => _checking = core ? 'core' : 'app');
    final port = s.running ? s.settings.mixedPort : null;
    try {
      final info = core ? await Updater.checkCore(s.coreRevision, proxyPort: port) : await Updater.checkApp(proxyPort: port);
      if (!mounted) return;
      await _showUpdate(core ? '内核' : 'SingFox', info, core: core);
    } catch (e) {
      if (mounted) toast(context, '检查更新失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _checking = null);
    }
  }

  Future<void> _showUpdate(String what, UpdateInfo info, {bool core = false}) {
    final (title, body) = !info.published
        ? ('$what 尚未发布版本', '发布页还没有正式版本。发布到 GitHub 后，这里会显示新版本与更新说明。')
        : info.newer
            ? ('发现新版本 ${info.tag}', info.notes.trim().isEmpty ? '（没有更新说明）' : info.notes.trim())
            : ('$what 已是最新', '当前版本与最新发布 ${info.tag} 一致。');
    return showDialog(
      context: context,
      barrierColor: const Color(0x9E000000),
      builder: (c) => Dialog(
        backgroundColor: SF.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: SF.t(16, weight: FontWeight.w600)),
              if (info.date != null) ...[
                const SizedBox(height: 4),
                Text('发布于 ${info.date!.toLocal().toString().substring(0, 16)}', style: SF.t(12, color: SF.text3)),
              ],
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(child: SelectableText(body, style: SF.t(13, color: SF.text2, height: 1.6))),
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                SFButton('关闭', onTap: () => Navigator.pop(c)),
                const SizedBox(width: 8),
                if (core && info.newer && info.installable) ...[
                  SFButton('打开发布页', onTap: () {
                    Process.run('explorer', [info.url]);
                    Navigator.pop(c);
                  }),
                  const SizedBox(width: 8),
                  SFButton('立即更新', kind: BtnKind.primary, onTap: () {
                    Navigator.pop(c);
                    _installCore(info);
                  }),
                ] else
                  SFButton(info.newer ? '前往下载' : '打开发布页', kind: BtnKind.primary, onTap: () {
                    Process.run('explorer', [info.url]);
                    Navigator.pop(c);
                  }),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
