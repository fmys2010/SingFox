import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/profiles.dart';
import '../../editor/config_editor.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

/// 增加配置 / 编辑配置: cloud subscription, local config text, or a file.
class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key, this.edit, this.kind});
  final Profile? edit;
  /// The tab a new config starts on.
  final ProfileKind? kind;

  static Future<void> open(BuildContext context, {Profile? edit, ProfileKind? kind}) => showDialog(
        context: context,
        barrierColor: const Color(0x9E000000),
        builder: (_) => ProfileDialog(edit: edit, kind: kind),
      );

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late ProfileKind _kind;
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _ua = TextEditingController(text: 'sing-box original-singbox-x');
  final _code = CodeLineEditingController();
  int _hours = 12;
  bool _viaProxy = false, _watch = true, _busy = false;
  String _file = '';
  String? _error;

  bool get _editing => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.edit;
    _kind = p?.kind ?? widget.kind ?? ProfileKind.cloud;
    if (p != null) {
      _name.text = p.name;
      _url.text = p.url;
      _ua.text = p.userAgent;
      _hours = p.updateHours;
      _viaProxy = p.updateViaProxy;
      _watch = p.watchFile;
      _file = p.filePath;
      if (p.kind == ProfileKind.local) {
        AppState.I.profiles.read(p).then((t) => _code.text = t, onError: (_) {});
      }
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(dialogTitle: '选择 sing-box 配置文件', type: FileType.custom, allowedExtensions: ['json']);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      _file = path;
      if (_name.text.isEmpty) _name.text = path.split(RegExp(r'[\\/]')).last;
    });
  }

  Future<void> _save() async {
    final s = AppState.I;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _name.text.trim().isEmpty
          ? switch (_kind) {
              ProfileKind.cloud => Uri.tryParse(_url.text)?.host ?? '订阅',
              ProfileKind.local => '本地配置',
              ProfileKind.file => _file.split(RegExp(r'[\\/]')).last,
            }
          : _name.text.trim();
      if (_kind == ProfileKind.cloud && !(_url.text.startsWith('http://') || _url.text.startsWith('https://'))) {
        throw const FormatException('请填写以 http(s):// 开头的订阅链接');
      }
      if (_kind == ProfileKind.file && _file.isEmpty) throw const FormatException('请先选择配置文件');
      if (_kind == ProfileKind.local) {
        final err = await checkWithCore(_code.text);
        if (err != null) throw FormatException(err);
      }

      final p = widget.edit ?? Profile(id: ProfileStore.newId(), name: name, kind: _kind);
      p
        ..name = name
        ..url = _url.text.trim()
        ..userAgent = _ua.text.trim()
        ..updateHours = _hours
        ..updateViaProxy = _viaProxy
        ..filePath = _file
        ..watchFile = _watch;
      if (_editing) {
        if (p.kind == ProfileKind.local) await s.profiles.writeLocal(p, _code.text);
        if (p.kind == ProfileKind.cloud) await s.profiles.update(p, proxyPort: s.running && _viaProxy ? s.settings.mixedPort : null);
        await s.saveProfile(p);
      } else {
        await s.addProfile(p, content: _kind == ProfileKind.local ? _code.text : null);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e is FormatException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [(ProfileKind.cloud, '云端配置', Icons.cloud_outlined), (ProfileKind.local, '本地配置', Icons.code_rounded), (ProfileKind.file, '本地文件', Icons.insert_drive_file_outlined)];
    return Dialog(
      backgroundColor: SF.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
      child: SizedBox(
        width: 580,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Text(_editing ? '编辑配置' : '增加配置', style: SF.t(16, weight: FontWeight.w600)),
              const Spacer(),
              SFIconButton(Icons.close_rounded, tooltip: '关闭', bordered: false, size: 30, onTap: () => Navigator.pop(context)),
            ]),
          ),
          if (!_editing)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: SF.bg, border: Border.all(color: const Color(0xFF222226)), borderRadius: BorderRadius.circular(9)),
              child: Stack(children: [
                // The highlight slides between the equal-width tabs.
                AnimatedAlign(
                  duration: SF.medium,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(-1 + 2 * tabs.indexWhere((e) => e.$1 == _kind) / (tabs.length - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / tabs.length,
                    child: Container(height: 32, decoration: BoxDecoration(color: SF.active, borderRadius: BorderRadius.circular(6))),
                  ),
                ),
                Row(children: [
                  for (final (k, label, icon) in tabs)
                    Expanded(
                      child: Tap(
                        radius: 6,
                        onTap: () => setState(() => _kind = k),
                        child: SizedBox(
                          height: 32,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(icon, size: 15, color: _kind == k ? SF.text : SF.text3),
                            const SizedBox(width: 7),
                            AnimatedDefaultTextStyle(
                              duration: SF.fast,
                              style: SF.t(13, color: _kind == k ? SF.text : SF.text3, weight: FontWeight.w500),
                              child: Text(label),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('名称'),
              SFInput(controller: _name, background: SF.bg, height: 36, hint: switch (_kind) { ProfileKind.cloud => '例如：机场 C', ProfileKind.local => '例如：自建 VPS', ProfileKind.file => '默认使用文件名' }),
              const SizedBox(height: 16),
              AnimatedSize(
                duration: SF.medium,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: SF.fast,
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  child: Column(
                    key: ValueKey(_kind),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: switch (_kind) { ProfileKind.cloud => _cloud(), ProfileKind.local => _local(), ProfileKind.file => _fileTab() },
                  ),
                ),
              ),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.error_outline_rounded, size: 14, color: SF.bad)),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: SF.t(12.5, color: SF.bad))),
              ]),
            ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: SF.lineInner))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              SFButton('取消', onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              SFButton(
                _busy ? '处理中…' : (_editing ? '保存' : switch (_kind) { ProfileKind.cloud => '导入订阅', ProfileKind.local => '校验并保存', ProfileKind.file => '添加文件' }),
                kind: BtnKind.primary,
                onTap: _busy ? null : _save,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _label(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [Text(t, style: SF.t(12.5, color: SF.text2)), const Spacer(), ?trailing]),
      );

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: SF.t(13, weight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text(sub, style: SF.t(12, color: SF.text3)),
          ]),
        ),
        SFSwitch(value: v, onChanged: (x) => setState(() => on(x))),
      ]);

  List<Widget> _cloud() => [
        _label('订阅链接'),
        SFInput(controller: _url, background: SF.bg, height: 36, mono: true, hint: 'https://example.com/api/v1/sub?token=…'),
        const SizedBox(height: 7),
        Text('订阅需返回 sing-box JSON 配置', style: SF.t(12, color: SF.text3)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('自动更新'),
              PopupMenuButton<int>(
                color: SF.raised,
                onSelected: (v) => setState(() => _hours = v),
                itemBuilder: (_) => [for (final h in [0, 6, 12, 24, 72]) PopupMenuItem(value: h, child: Text(h == 0 ? '不自动更新' : '每 $h 小时', style: SF.t(13)))],
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: SF.bg, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Text(_hours == 0 ? '不自动更新' : '每 $_hours 小时', style: SF.t(13)),
                    const Spacer(),
                    const Icon(Icons.expand_more_rounded, size: 16, color: SF.text3),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('User-Agent'),
              SFInput(controller: _ua, background: SF.bg, height: 36, mono: true),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _switchRow('通过当前代理更新', '订阅地址无法直连时开启（需内核运行中）', _viaProxy, (v) => _viaProxy = v),
      ];

  List<Widget> _local() => [
        _label('配置内容',
            trailing: Row(children: [
              const OutlineTag('sing-box JSON'),
              const SizedBox(width: 8),
              SFIconButton(Icons.open_in_full_rounded, tooltip: '放大编辑', size: 26, iconSize: 13, onTap: () => BigEditorDialog.open(context, _code, _name.text.isEmpty ? '本地配置' : _name.text)),
            ])),
        Container(
          height: 240,
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: SF.bg, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: ConfigCodeEditor(controller: _code),
        ),
        const SizedBox(height: 7),
        Text('输入时按 sing-box schema 补全字段；保存前会用内核 sing-box check 校验', style: SF.t(12, color: SF.text3)),
      ];

  List<Widget> _fileTab() => [
        _label('配置文件'),
        Tap(
          radius: 10,
          onTap: _pick,
          child: Container(
            height: 150,
            decoration: BoxDecoration(color: const Color(0xFF0C0C0E), border: Border.all(color: const Color(0xFF3A3A40)), borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: SF.raised, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.upload_rounded, size: 18, color: SF.text2),
              ),
              const SizedBox(height: 10),
              if (_file.isEmpty)
                Text.rich(TextSpan(children: [TextSpan(text: '点击', style: SF.t(13)), TextSpan(text: '选择文件', style: SF.t(13, color: SF.accent))]))
              else
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_file, style: SF.m(12), overflow: TextOverflow.ellipsis)),
              const SizedBox(height: 6),
              Text('.json · sing-box 配置', style: SF.m(12, color: SF.text3)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _switchRow('引用原文件', '每次启动都读取该文件的最新内容，不复制到 SingFox 目录', _watch, (v) => _watch = v),
      ];
}
