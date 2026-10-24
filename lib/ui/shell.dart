import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/profiles.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dialogs/profile_dialog.dart';
import 'pages/connections.dart';
import 'pages/logs.dart';
import 'pages/nodes.dart';
import 'pages/overview.dart';
import 'pages/rules.dart';
import 'pages/settings.dart';
import 'tray.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

const _nav = <(String, IconData)>[
  ('概览', Icons.grid_view_rounded),
  ('代理节点', Icons.public_rounded),
  ('连接', Icons.timeline_rounded),
  ('规则', Icons.sort_rounded),
  ('日志', Icons.article_outlined),
  ('设置', Icons.tune_rounded),
];

class _ShellState extends State<Shell> with WindowListener {
  int _page = 0;
  bool _menu = false;
  final s = AppState.I;

  /// State changed while the window was hidden; rebuild once it shows.
  bool _stale = false;

  // The core reports traffic and connections every second. While the window
  // is minimised or in the tray nobody sees the UI, so skip those rebuilds.
  void _onState() {
    if (!mounted) return;
    if (appVisible.value) {
      setState(() {});
    } else {
      _stale = true;
    }
  }

  void _onVisible() {
    if (appVisible.value && _stale && mounted) setState(() => _stale = false);
  }

  @override
  void onWindowEvent(String eventName) {
    switch (eventName) {
      case 'minimize' || 'hide':
        appVisible.value = false;
      case 'restore' || 'show' || 'focus':
        appVisible.value = true;
    }
  }

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
    appVisible.addListener(_onVisible);
    windowManager.addListener(this);
    // Development hooks for scripted checks: open a page / connect on launch.
    _page = int.tryParse(Platform.environment['SINGFOX_PAGE'] ?? '') ?? 0;
    // Delayed so the overview is on screen first, like a real click.
    if (Platform.environment['SINGFOX_AUTOSTART'] == '1') Future.delayed(const Duration(seconds: 1), s.start);
    final stopAfter = double.tryParse(Platform.environment['SINGFOX_AUTOSTOP'] ?? '');
    if (stopAfter != null) Future.delayed(Duration(milliseconds: (stopAfter * 1000).round()), s.stop);
    // SINGFOX_AUTOQUIT=seconds runs the tray's 退出 path.
    final quitAfter = double.tryParse(Platform.environment['SINGFOX_AUTOQUIT'] ?? '');
    if (quitAfter != null) Future.delayed(Duration(milliseconds: (quitAfter * 1000).round()), SFTray.quit);
    // SINGFOX_DIALOG=cloud|local|file opens 增加配置 on that tab.
    final dialog = ProfileKind.values.where((k) => k.name == Platform.environment['SINGFOX_DIALOG']).firstOrNull;
    if (dialog != null) WidgetsBinding.instance.addPostFrameCallback((_) => ProfileDialog.open(context, kind: dialog));
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    appVisible.removeListener(_onVisible);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (s.settings.showTray && s.settings.closeToTray) {
      appVisible.value = false;
      return windowManager.hide();
    }
    await SFTray.quit();
  }

  void go(int i) => setState(() => _page = i);

  @override
  Widget build(BuildContext context) => Scaffold(
        // Animations pause while hidden (the planet's orbit would keep
        // ticking at 60 fps in the tray otherwise).
        body: ValueListenableBuilder<bool>(
          valueListenable: appVisible,
          builder: (context, visible, child) => TickerMode(enabled: visible, child: child!),
          child: Stack(children: [
            Column(children: [
              const _TitleBar(),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _sidebar(),
                  Expanded(
                    child: FadeSlideSwitcher(
                      child: KeyedSubtree(
                        key: ValueKey(_page),
                        // Fresh (non-const) instances so pages rebuild on every state change.
                        child: switch (_page) {
                          0 => OverviewPage(onGo: go),
                          1 => NodesPage(),
                          2 => ConnectionsPage(),
                          3 => RulesPage(),
                          4 => LogsPage(),
                          _ => SettingsPage(),
                        },
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
            if (_menu) ...[
              Positioned.fill(child: GestureDetector(onTap: () => setState(() => _menu = false), behavior: HitTestBehavior.opaque)),
              Positioned(
                left: 12,
                top: 112,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: SF.medium,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(offset: Offset(0, -6 * (1 - v)), child: child),
                  ),
                  child: _ConfigMenu(onClose: () => setState(() => _menu = false)),
                ),
              ),
            ],
          ]),
        ),
      );

  Widget _sidebar() {
    final p = s.active;
    final meta = p == null ? '点击增加配置' : _profileMeta(p);
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: SF.lineSoft))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Tap(
          radius: 10,
          onTap: () => setState(() => _menu = !_menu),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _menu ? SF.raised : SF.surface,
              border: Border.all(color: _menu ? const Color(0xFF2E2E33) : SF.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              _Avatar(p?.initial ?? '+'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p?.name ?? '还没有配置', style: SF.t(13, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(meta, style: SF.t(11.5, color: SF.text3), overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.unfold_more_rounded, size: 16, color: SF.text3),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _nav.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Tap(
              onTap: () => go(i),
              child: AnimatedContainer(
                duration: SF.fast,
                curve: Curves.easeOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: i == _page ? SF.raised : SF.raised.withValues(alpha: 0), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: i == _page ? SF.accent : SF.text3),
                    duration: SF.fast,
                    builder: (context, c, _) => Icon(_nav[i].$2, size: 17, color: c),
                  ),
                  const SizedBox(width: 11),
                  AnimatedDefaultTextStyle(
                    duration: SF.fast,
                    style: SF.t(13.5, color: i == _page ? SF.text : SF.text2, weight: FontWeight.w500),
                    child: Text(_nav[i].$1),
                  ),
                ]),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 2),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: SF.lineSoft))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Dot(switch (s.status) {
                CoreStatus.running => SF.ok,
                CoreStatus.stopped => s.error != null ? SF.bad : SF.faint,
                _ => SF.warn,
              }),
              const SizedBox(width: 8),
              Text(
                switch (s.status) {
                  CoreStatus.running => '内核运行中',
                  CoreStatus.starting => '正在启动…',
                  CoreStatus.stopping => '正在停止…',
                  CoreStatus.stopped => s.coreBinary == null ? '未找到内核' : '内核未运行',
                },
                style: SF.t(12, color: SF.text3),
              ),
              const Spacer(),
              if (s.running) Text(fmtBytes(s.memory), style: SF.m(12, color: SF.text3)),
            ]),
            const SizedBox(height: 6),
            Text('sing-box ${s.coreVersion.isEmpty ? '—' : s.coreVersion}', style: SF.m(12, color: SF.text2), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

String _profileMeta(Profile p) {
  if (p.kind == ProfileKind.cloud && p.total != null && p.total! > 0) {
    final left = p.total! - (p.upload ?? 0) - (p.download ?? 0);
    final days = p.expire?.difference(DateTime.now()).inDays;
    return '剩余 ${fmtBytes(left < 0 ? 0 : left)}${days == null ? '' : ' · $days 天'}';
  }
  return switch (p.kind) {
    ProfileKind.cloud => '云端 · ${fmtAgo(p.updatedAt)}更新',
    ProfileKind.local => '本地配置',
    ProfileKind.file => p.filePath.split(RegExp(r'[\\/]')).last,
  };
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.letter, {this.size = 28});
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF222226), borderRadius: BorderRadius.circular(size / 4)),
        child: Text(letter, style: SF.t(size * .43, weight: FontWeight.w600)),
      );
}

class _ConfigMenu extends StatelessWidget {
  const _ConfigMenu({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        border: Border.all(color: SF.input),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 6), child: Text('配置', style: SF.t(11.5, color: SF.text3))),
        for (final p in s.profiles.items)
          Container(
            decoration: BoxDecoration(color: p.id == s.settings.activeProfile ? const Color(0xFF1C1C1F) : null, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(
                child: Tap(
                  onTap: () {
                    onClose();
                    if (p.id != s.settings.activeProfile) s.activate(p);
                  },
                  child: SizedBox(
                    height: 48,
                    child: Row(children: [
                      const SizedBox(width: 10),
                      _Avatar(p.initial, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: SF.t(13, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          Text('${p.kindLabel} · ${_profileMeta(p)}', style: SF.t(11.5, color: SF.text3), overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      if (p.id == s.settings.activeProfile) const Icon(Icons.check_rounded, size: 15, color: SF.accent),
                      const SizedBox(width: 4),
                    ]),
                  ),
                ),
              ),
              SFIconButton(Icons.settings_outlined, tooltip: '设置 ${p.name}', bordered: false, size: 30, onTap: () {
                onClose();
                ProfileDialog.open(context, edit: p);
              }),
              SFIconButton(Icons.delete_outline_rounded, tooltip: '删除 ${p.name}', bordered: false, size: 30, onTap: () async {
                onClose();
                final ok = await confirm(context, '删除配置“${p.name}”？', p.kind == ProfileKind.file ? '只移除引用，不会删除原文件。' : '删除后无法恢复。');
                if (ok) await s.removeProfile(p);
              }),
              const SizedBox(width: 4),
            ]),
          ),
        Container(height: 1, color: const Color(0xFF222226), margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
        Tap(
          onTap: () {
            onClose();
            ProfileDialog.open(context);
          },
          child: SizedBox(
            height: 40,
            child: Row(children: [
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3A40)), borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.add_rounded, size: 14, color: SF.text2),
              ),
              const SizedBox(width: 10),
              Text('增加配置', style: SF.t(13, weight: FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = '删除'}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x9E000000),
    builder: (c) => Dialog(
      backgroundColor: SF.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: SF.t(16, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(body, style: SF.t(13, color: SF.text2)),
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              SFButton('取消', onTap: () => Navigator.pop(c, false)),
              const SizedBox(width: 8),
              SFButton(ok, kind: BtnKind.primary, onTap: () => Navigator.pop(c, true)),
            ]),
          ]),
        ),
      ),
    ),
  );
  return r ?? false;
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux;
    return Container(
      height: 40,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineSoft))),
      child: Row(children: [
        Expanded(
          child: DragToMoveArea(
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(left: 16),
              child: Row(children: [
                CustomPaint(size: const Size(18, 18), painter: AppMark()),
                const SizedBox(width: 10),
                Text('SingFox', style: SF.t(13, weight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
        if (desktop) ...[
          _WinBtn(Icons.remove_rounded, '最小化', () => windowManager.minimize()),
          _WinBtn(Icons.crop_square_rounded, '最大化', () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          }),
          _WinBtn(Icons.close_rounded, '关闭', () => windowManager.close(), danger: true),
        ],
      ]),
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _h = true),
          onExit: (_) => setState(() => _h = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 46,
              height: 40,
              color: _h ? (widget.danger ? const Color(0xFFC42B1C) : const Color(0x14FFFFFF)) : Colors.transparent,
              child: Icon(widget.icon, size: 14, color: _h && widget.danger ? Colors.white : SF.text3),
            ),
          ),
        ),
      );
}

/// The SingFox mark: an orange parcel box, drawn from assets/icon/singfox.svg
/// (512 × 512 viewBox) so it stays crisp at any size.
class AppMark extends CustomPainter {
  static final _faces = <(int, Path)>[
    (0xFF9C4A1C, Path()
      ..moveTo(88, 187)
      ..lineTo(254, 300)
      ..lineTo(254, 436)
      ..quadraticBezierTo(247, 436, 240, 432)
      ..lineTo(103, 341)
      ..quadraticBezierTo(88, 331, 88, 314)
      ..close()),
    (0xFFC25E26, Path()
      ..moveTo(254, 300)
      ..lineTo(422, 187)
      ..lineTo(422, 314)
      ..quadraticBezierTo(422, 330, 408, 340)
      ..lineTo(266, 432)
      ..quadraticBezierTo(260, 436, 254, 436)
      ..close()),
    (0xFFE8834A, Path()
      ..moveTo(88, 187)
      ..quadraticBezierTo(87, 181, 96, 175)
      ..lineTo(237, 79)
      ..quadraticBezierTo(253, 69, 268, 79)
      ..lineTo(414, 176)
      ..quadraticBezierTo(422, 181, 422, 190)
      ..lineTo(254, 300)
      ..close()),
    (0xFFE8834A, Path()
      ..moveTo(242, 292)
      ..lineTo(266, 292)
      ..lineTo(266, 423)
      ..quadraticBezierTo(266, 432, 258, 436)
      ..quadraticBezierTo(253, 438, 248, 434)
      ..quadraticBezierTo(242, 431, 242, 423)
      ..close()),
    (0xFFF6D7C2, Path()
      ..moveTo(139, 145)
      ..lineTo(173, 122)
      ..lineTo(350, 243)
      ..lineTo(314, 266)
      ..close()),
    (0xFFFCEBDD, Path()
      ..moveTo(173, 122)
      ..lineTo(195, 107)
      ..lineTo(373, 227)
      ..lineTo(350, 243)
      ..close()),
    (0xFFE2B293, Path()
      ..moveTo(314, 266)
      ..lineTo(350, 243)
      ..lineTo(350, 294)
      ..quadraticBezierTo(350, 300, 344, 304)
      ..lineTo(330, 313)
      ..quadraticBezierTo(323, 317, 318, 311)
      ..quadraticBezierTo(314, 308, 314, 301)
      ..close()),
    (0xFFF3CDB3, Path()
      ..moveTo(350, 243)
      ..lineTo(373, 227)
      ..lineTo(373, 269)
      ..quadraticBezierTo(373, 279, 364, 286)
      ..lineTo(350, 296)
      ..close()),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 512, size.height / 512);
    for (final (color, path) in _faces) {
      canvas.drawPath(path, Paint()..color = Color(color));
    }
  }

  @override
  bool shouldRepaint(AppMark oldDelegate) => false;
}
