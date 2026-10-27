import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/android_core.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'mobile_widgets.dart';

typedef _App = ({String package, String label});

/// Per-app routing: pick the apps that skip the VPN, or the only ones that use it.
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key});

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  final s = AppState.I;
  List<_App>? _apps;
  String _q = '';
  late String _mode = s.settings.appMode;
  late final Set<String> _picked = {...s.settings.appList};
  final _icons = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    AndroidCore.I.apps().then((l) {
      if (mounted) setState(() => _apps = l);
    }, onError: (_) {
      if (mounted) setState(() => _apps = []);
    });
  }

  /// Saves and, when the VPN is up, reconnects so the new routing takes effect.
  Future<void> _save() async {
    final st = s.settings;
    final changed = st.appMode != _mode || st.appList.toSet().difference(_picked).isNotEmpty || _picked.difference(st.appList.toSet()).isNotEmpty;
    if (!changed) return;
    await s.updateSettings((x) {
      x.appMode = _mode;
      x.appList = _picked.toList()..sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final q = _q.trim().toLowerCase();
    final shown = apps == null ? <_App>[] : [for (final a in apps) if (q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q)) a];
    // Picked apps first, so the current choice is easy to review.
    shown.sort((a, b) => (_picked.contains(b.package) ? 1 : 0) - (_picked.contains(a.package) ? 1 : 0));
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        backgroundColor: SF.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: SF.text2), onPressed: () => Navigator.of(context).maybePop()),
                Text('应用分流', style: SF.t(18, weight: FontWeight.w600)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: MSegmented<String>(
                options: const [('all', '全部走 VPN'), ('bypass', '所选绕过'), ('only', '仅所选走')],
                value: _mode,
                onChanged: (v) => setState(() => _mode = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  switch (_mode) {
                    'bypass' => '勾选的应用直接上网，不经过 VPN，更省电、更快。',
                    'only' => '只有勾选的应用走 VPN，其余直接上网。',
                    _ => '所有应用都走 VPN，下方选择不生效。',
                  },
                  style: SF.t(12, color: SF.text3),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: MSearch(hint: '搜索应用', onChanged: (v) => setState(() => _q = v))),
            const SizedBox(height: 8),
            Expanded(
              child: apps == null
                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: SF.accent)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final a = shown[i];
                        final on = _picked.contains(a.package);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => on ? _picked.remove(a.package) : _picked.add(a.package)),
                          child: Container(
                            height: 60,
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineInner))),
                            child: Row(children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: FutureBuilder<Uint8List?>(
                                  future: _icons.putIfAbsent(a.package, () => AndroidCore.I.appIcon(a.package)),
                                  builder: (_, snap) => snap.data == null ? const SizedBox() : Image.memory(snap.data!, gaplessPlayback: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SF.t(14.5, weight: FontWeight.w500)),
                                  Text(a.package, maxLines: 1, overflow: TextOverflow.ellipsis, style: SF.m(11, color: SF.text3)),
                                ]),
                              ),
                              Icon(on ? Icons.check_box : Icons.check_box_outline_blank, color: on ? SF.accent : SF.faint),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
