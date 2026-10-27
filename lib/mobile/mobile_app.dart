import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/profiles.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../ui/widgets.dart';
import 'mobile_pages.dart';
import 'mobile_widgets.dart';

class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SingFox',
        debugShowCheckedModeBanner: false,
        theme: SF.theme(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: SF.bg,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: child!,
        ),
        home: const MobileShell(),
      );
}

const _tabs = <(String, IconData)>[
  ('概览', Icons.grid_view_rounded),
  ('节点', Icons.public_rounded),
  ('连接', Icons.timeline_rounded),
  ('设置', Icons.tune_rounded),
];

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> with WidgetsBindingObserver {
  final s = AppState.I;
  int _page = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The core reports traffic every second; nobody sees it while backgrounded.
  void _onState() {
    if (mounted && _foreground) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    s.setForeground(fg);
    if (fg != _foreground) {
      _foreground = fg;
      if (fg && mounted) setState(() {});
    }
  }

  void _go(int i) => setState(() => _page = i);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SF.bg,
        body: SafeArea(
          bottom: false,
          child: FadeSlideSwitcher(
            child: KeyedSubtree(
              key: ValueKey(_page),
              // Fresh (non-const) instances so pages rebuild on every state change.
              child: switch (_page) {
                0 => MOverviewPage(onProfiles: () => showProfiles(context), onGo: _go),
                1 => MNodesPage(),
                2 => MConnectionsPage(),
                _ => MSettingsPage(),
              },
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: SF.bg, border: Border(top: BorderSide(color: SF.lineSoft))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == _page,
                      label: _tabs[i].$1,
                      child: GestureDetector(
                        onTap: () => _go(i),
                        behavior: HitTestBehavior.opaque,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          TweenAnimationBuilder<Color?>(
                            tween: ColorTween(end: i == _page ? SF.accent : SF.text3),
                            duration: SF.fast,
                            builder: (context, c, _) => Icon(_tabs[i].$2, size: 24, color: c),
                          ),
                          const SizedBox(height: 4),
                          Text(_tabs[i].$1, style: SF.t(11, color: i == _page ? SF.accent : SF.text3, weight: FontWeight.w500)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- profiles sheet

Future<void> showProfiles(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141416),
      barrierColor: const Color(0x9E000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)), side: BorderSide(color: SF.input)),
      builder: (_) => const _ProfileSheet(),
    );

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final s = AppState.I;

  Future<void> _delete(Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: SF.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
        title: Text('删除配置“${p.name}”？', style: SF.t(16, weight: FontWeight.w600)),
        content: Text(p.kind == ProfileKind.file ? '只移除引用，不会删除原文件。' : '删除后无法恢复。', style: SF.t(13, color: SF.text2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('取消', style: SF.t(14, color: SF.text2))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('删除', style: SF.t(14, color: SF.bad))),
        ],
      ),
    );
    if (ok == true) {
      await s.removeProfile(p);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = s.profiles.items;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A40), borderRadius: BorderRadius.circular(2)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
            child: Row(children: [
              Text('配置', style: SF.t(16, weight: FontWeight.w600)),
              const Spacer(),
              Text('${items.length} 个', style: SF.t(12, color: SF.text3)),
            ]),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in items)
                Container(
                  height: 64,
                  decoration: BoxDecoration(color: p.id == s.settings.activeProfile ? const Color(0xFF1C1C1F) : null, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.pop(context);
                          if (p.id != s.settings.activeProfile) s.activate(p);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: const Color(0xFF222226), borderRadius: BorderRadius.circular(9)),
                              child: Text(p.initial, style: SF.t(15, weight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: SF.t(14.5, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Text(profileMeta(p).startsWith(p.kindLabel) ? profileMeta(p) : '${p.kindLabel} · ${profileMeta(p)}', style: SF.t(12, color: SF.text3), overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                            if (p.id == s.settings.activeProfile) const Icon(Icons.check_rounded, size: 18, color: SF.accent),
                          ]),
                        ),
                      ),
                    ),
                    IconButton(onPressed: () => _delete(p), tooltip: '删除 ${p.name}', icon: const Icon(Icons.delete_outline_rounded, size: 20, color: SF.text3)),
                  ]),
                ),
            ]),
          ),
          Container(height: 1, color: const Color(0xFF222226), margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await showAddProfile(context);
              if (mounted) setState(() {});
            },
            child: SizedBox(
              height: 52,
              child: Row(children: [
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3A40)), borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.add_rounded, size: 18, color: SF.text2),
                ),
                const SizedBox(width: 12),
                Text('增加配置', style: SF.t(14.5, weight: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> showAddProfile(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141416),
      barrierColor: const Color(0x9E000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)), side: BorderSide(color: SF.input)),
      builder: (_) => const _AddProfile(),
    );

class _AddProfile extends StatefulWidget {
  const _AddProfile();

  @override
  State<_AddProfile> createState() => _AddProfileState();
}

class _AddProfileState extends State<_AddProfile> {
  final _name = TextEditingController(), _body = TextEditingController();
  ProfileKind _kind = ProfileKind.cloud;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (t != null) setState(() => _body.text = t.trim());
  }

  Future<void> _save() async {
    final text = _body.text.trim();
    if (text.isEmpty) return setState(() => _error = _kind == ProfileKind.cloud ? '请输入订阅链接' : '请粘贴配置内容');
    final name = _name.text.trim().isEmpty ? (_kind == ProfileKind.cloud ? (Uri.tryParse(text)?.host ?? '订阅') : '本地配置') : _name.text.trim();
    final p = Profile(id: ProfileStore.newId(), name: name, kind: _kind);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_kind == ProfileKind.cloud) {
        p.url = text;
        await AppState.I.addProfile(p);
      } else {
        await AppState.I.addProfile(p, content: text);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _field(TextEditingController c, String hint, {int lines = 1, bool mono = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: SF.surface, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(10)),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines,
          cursorColor: SF.accent,
          style: mono ? SF.m(13) : SF.t(14.5),
          decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: SF.t(14, color: SF.text3)),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF3A3A40), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('增加配置', style: SF.t(16, weight: FontWeight.w600)),
              const SizedBox(height: 14),
              MSegmented<ProfileKind>(
                options: const [(ProfileKind.cloud, '订阅链接'), (ProfileKind.local, '粘贴 JSON')],
                value: _kind,
                onChanged: (v) => setState(() {
                  _kind = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              _field(_name, '名称（可选）'),
              const SizedBox(height: 10),
              _field(_body, _kind == ProfileKind.cloud ? 'https://…  sing-box 格式订阅' : '粘贴 sing-box JSON 配置', lines: _kind == ProfileKind.cloud ? 2 : 6, mono: true),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 16, color: SF.text2),
                  label: Text('从剪贴板粘贴', style: SF.t(13, color: SF.text2)),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: SF.t(12.5, color: SF.bad), maxLines: 3, overflow: TextOverflow.ellipsis)),
              MButton(_busy ? '添加中…' : '添加', kind: MBtn.primary, onTap: _busy ? null : _save),
            ]),
          ),
        ),
      );
}
