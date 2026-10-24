import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _level = '全部', _q = '';
  bool _follow = true;
  List<LogLine>? _paused;
  final _sc = ScrollController();

  // Memoised view of the log; see build.
  (int, int, List<LogLine>?, int, String, String)? _key;
  List<LogLine> _all = const [], _list = const [];
  Map<String, int> _counts = const {};

  static const _levels = {'全部': null, '调试': {'DEBUG', 'TRACE'}, '信息': {'INFO'}, '警告': {'WARN'}, '错误': {'ERROR', 'FATAL', 'PANIC'}};

  (Color, Color, Color) _style(String lv) => switch (lv) {
        'WARN' => (SF.warn, SF.text, SF.warn.withValues(alpha: .05)),
        'ERROR' || 'FATAL' || 'PANIC' => (SF.bad, SF.text, SF.bad.withValues(alpha: .07)),
        'DEBUG' || 'TRACE' => (SF.text3, SF.text2, Colors.transparent),
        _ => (SF.text2, const Color(0xFFD4D4D8), Colors.transparent),
      };

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final keep = s.settings.logLines;
    // The page rebuilds every second with the traffic; redo the copy, filter
    // and counts only when the lines or the filters actually changed.
    final key = (_paused == null ? s.logTotal : -1, s.logs.length, _paused, keep, _level, _q);
    if (key != _key) {
      final grew = _key == null || key.$1 != _key!.$1;
      _key = key;
      final source = _paused ?? s.logs.toList();
      final all = source.length > keep ? source.sublist(source.length - keep) : source;
      _counts = {for (final MapEntry(key: k, value: lv) in _levels.entries) k: lv == null ? all.length : all.where((l) => lv.contains(l.level)).length};
      final lv = _levels[_level];
      var list = lv == null ? all : all.where((l) => lv.contains(l.level)).toList();
      if (_q.isNotEmpty) {
        final q = _q.toLowerCase();
        list = list.where((l) => l.message.toLowerCase().contains(q) || l.module.toLowerCase().contains(q)).toList();
      }
      _all = all;
      _list = list;
      if (grew && _follow && _paused == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
        });
      }
    }
    final all = _all, list = _list;
    int count(Set<String>? lv) => _counts[_levels.entries.firstWhere((e) => e.value == lv).key] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          '日志',
          subtitle: Row(children: [
            Dot(s.running && _paused == null ? SF.ok : SF.faint),
            const SizedBox(width: 6),
            Text('${_paused != null ? '已暂停' : (s.running ? '实时' : '内核未运行')} · '),
            Text('${s.logTotal}', style: SF.m(12.5, color: SF.text3)),
            const Text(' 条'),
          ]),
          actions: [
            SFInput(icon: Icons.search_rounded, hint: '搜索日志内容', width: 240, onChanged: (v) => setState(() => _q = v)),
            SFIconButton(_paused == null ? Icons.pause_rounded : Icons.play_arrow_rounded, tooltip: _paused == null ? '暂停' : '继续',
                onTap: () => setState(() => _paused = _paused == null ? s.logs.toList() : null)),
            SFIconButton(Icons.delete_outline_rounded, tooltip: '清空', onTap: () => setState(() {
                  s.logs.clear();
                  _paused = null;
                })),
            SFButton('导出', icon: Icons.download_rounded, onTap: () => _export(all)),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          Segmented<String>(
            options: [for (final k in _levels.keys) (k, '$k ${count(_levels[k])}')],
            value: _level,
            onChanged: (v) => setState(() => _level = v),
          ),
          const Spacer(),
          Text('显示行数', style: SF.t(12.5, color: SF.text2)),
          const SizedBox(width: 10),
          Segmented<int>(
            options: const [(200, '200'), (500, '500'), (1000, '1000')],
            value: s.settings.logLines,
            mono: true,
            dense: true,
            onChanged: (v) => s.updateSettings((x) => x.logLines = v, restart: false),
          ),
          const SizedBox(width: 20),
          Text('自动滚动', style: SF.t(12.5, color: SF.text2)),
          const SizedBox(width: 10),
          SFSwitch(small: true, value: _follow, onChanged: (v) => setState(() => _follow = v)),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: SFCard(
            padding: EdgeInsets.zero,
            color: const Color(0xFF0E0E10),
            child: Column(children: [
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text('暂无日志', style: SF.t(12.5, color: SF.text3)))
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _sc,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          itemCount: list.length,
                          itemExtent: 25,
                          itemBuilder: (context, i) {
                            final l = list[i];
                            final (lc, mc, bg) = _style(l.level);
                            return Container(
                              color: bg,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(children: [
                                SizedBox(width: 100, child: Text(l.time, style: SF.m(12, color: SF.text3))),
                                SizedBox(width: 60, child: Text(l.level, style: SF.m(12, color: lc, weight: FontWeight.w500))),
                                SizedBox(width: 190, child: Text(l.module, style: SF.m(12, color: SF.text2), overflow: TextOverflow.ellipsis)),
                                Expanded(child: Text(l.message, style: SF.m(12, color: mc), overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ]),
                            );
                          },
                        ),
                      ),
              ),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: SF.lineInner))),
                child: Row(children: [
                  Text('级别 ', style: SF.t(12, color: SF.text3)),
                  Text(s.settings.logLevel, style: SF.m(12, color: SF.text2)),
                  Text(' · 显示最近 ${s.settings.logLines} 条', style: SF.t(12, color: SF.text3)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _export(List<LogLine> lines) async {
    final path = await FilePicker.platform.saveFile(dialogTitle: '导出日志', fileName: 'singfox-${DateTime.now().millisecondsSinceEpoch}.log');
    if (path == null) return;
    await File(path).writeAsString(lines.map((l) => '${l.time} ${l.level} ${l.module}: ${l.message}').join('\n'));
    if (mounted) toast(context, '已导出到 $path');
  }
}
