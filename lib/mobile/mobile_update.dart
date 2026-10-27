import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/android_core.dart';
import '../core/updater.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'mobile_widgets.dart';

/// Checks for a newer SingFox (the sing-box core is bundled in the APK, so one
/// update covers both) or a newer core, and installs the APK in place.
Future<void> showUpdate(BuildContext context, {required bool core}) =>
    showDialog(context: context, builder: (_) => _UpdateDialog(core: core));

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.core});
  final bool core;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final s = AppState.I;
  UpdateInfo? _info; // the SingFox release to install
  UpdateInfo? _coreInfo; // the newest core release (core check only)
  String? _error;
  double? _progress;
  bool _checking = true;

  int? get _port => s.running ? s.settings.mixedPort : null;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final app = await Updater.checkApp(proxyPort: _port);
      final core = widget.core ? await Updater.checkBundledCore(s.coreVersion, proxyPort: _port) : null;
      if (mounted) setState(() => _info = app);
      _coreInfo = core;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _install(UpdateInfo info) async {
    final abis = await AndroidCore.I.abis();
    final apk = info.apkFor(abis);
    if (apk == null) {
      setState(() => _error = '这个版本没有适合本机（${abis.join('、')}）的安装包');
      return;
    }
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
      final f = await Updater.download(apk.url, File('${dir.path}/${apk.name}'),
          sha256: info.sha256ForApk(apk.name), proxyPort: _port, onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      final r = await AndroidCore.I.installApk(f.path);
      if (!mounted) return;
      if (r == 'needs_permission') {
        setState(() {
          _progress = null;
          _error = '请在打开的设置页允许 SingFox 安装应用，然后回来再点一次“下载并安装”';
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = '更新失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final coreInfo = _coreInfo;
    final what = widget.core ? '内核' : 'SingFox';
    String title;
    String body;
    if (_checking) {
      title = '正在检查更新…';
      body = '';
    } else if (info == null || !info.published) {
      title = _error != null ? '检查更新失败' : '$what 尚未发布版本';
      body = _error ?? '发布页还没有版本。';
    } else if (info.newer) {
      title = '发现 SingFox ${info.tag}';
      body = info.notes.trim().isEmpty ? '（没有更新说明）' : info.notes.trim();
      if (widget.core && coreInfo != null && coreInfo.newer) body = '内核最新为 ${coreInfo.tag}，随这次更新一起提供。\n\n$body';
    } else if (widget.core && coreInfo != null && coreInfo.newer) {
      title = '内核 ${coreInfo.tag} 已发布';
      body = '当前内核 ${s.coreVersion}。安卓版的内核内置在应用里，等下一个 SingFox 版本发布后即可一并更新。';
    } else {
      title = '$what 已是最新';
      body = widget.core ? '内核 ${s.coreVersion}，应用 ${Updater.appVersion}。' : '当前版本 ${Updater.appVersion} 与最新发布 ${info.tag} 一致。';
    }
    final canInstall = info != null && info.newer && info.assets.any((a) => a.name.endsWith('.apk'));
    return Dialog(
      backgroundColor: SF.raised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: SF.line)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: SF.t(17, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_checking)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: SF.accent)))
            else
              Flexible(child: SingleChildScrollView(child: Text(body, style: SF.t(13, color: SF.text2, height: 1.5)))),
            if (_error != null && !_checking && body != _error) ...[
              const SizedBox(height: 10),
              Text(_error!, style: SF.t(12.5, color: SF.bad)),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: _progress, minHeight: 4, color: SF.accent, backgroundColor: SF.input)),
              const SizedBox(height: 6),
              Text('下载中 ${((_progress ?? 0) * 100).round()}%', style: SF.m(12, color: SF.text3)),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: MButton('关闭', onTap: _progress != null ? null : () => Navigator.of(context).pop())),
              if (canInstall) ...[
                const SizedBox(width: 10),
                Expanded(child: MButton('下载并安装', kind: MBtn.primary, onTap: _progress != null ? null : () => _install(info))),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
