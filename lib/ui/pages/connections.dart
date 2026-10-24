import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  int _tab = 0;
  String _q = '';
  List<Conn>? _frozen;

  static const _cols = [3, 2, 2, 2, 1];

  Color _dot(Conn c) {
    final out = c.chains.isEmpty ? '' : c.chains.first.toLowerCase();
    final rule = c.rule.toLowerCase();
    if (rule.contains('reject') || out.contains('block') || out.contains('reject')) return SF.bad;
    if (out == 'direct' || rule.contains('direct')) return const Color(0xFF71717A);
    return SF.accent;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    var list = _frozen ?? (_tab == 0 ? s.conns : s.closed.toList());
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list.where((c) => c.host.toLowerCase().contains(q) || c.process.toLowerCase().contains(q) || c.rule.toLowerCase().contains(q)).toList();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          '连接',
          subtitle: Text.rich(TextSpan(children: [
            TextSpan(text: '${s.conns.length}', style: SF.m(12.5, color: SF.text3)),
            const TextSpan(text: ' 个活动连接 · ↓ '),
            TextSpan(text: '${fmtBytes(s.down)}/s', style: SF.m(12.5, color: SF.text3)),
            const TextSpan(text: ' · ↑ '),
            TextSpan(text: '${fmtBytes(s.up)}/s', style: SF.m(12.5, color: SF.text3)),
          ])),
          actions: [
            SFInput(icon: Icons.search_rounded, hint: '按域名、进程、规则过滤', width: 240, onChanged: (v) => setState(() => _q = v)),
            SFButton(_frozen == null ? '暂停' : '继续', onTap: () => setState(() => _frozen = _frozen == null ? list : null)),
            SFButton('全部关闭', kind: BtnKind.danger, onTap: s.running ? s.closeAll : null),
          ],
        ),
        const SizedBox(height: 16),
        UnderlineTabs(
          items: [('活动中', '${s.conns.length}'), ('已关闭', '${s.closed.length}')],
          index: _tab,
          onChanged: (i) => setState(() {
            _tab = i;
            _frozen = null;
          }),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SFCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
                child: DefaultTextStyle(
                  style: SF.t(12, color: SF.text3),
                  child: Row(children: [
                    for (final (i, t) in ['目标', '规则', '出站', '上传 / 下载', '时长'].indexed) Expanded(flex: _cols[i], child: Text(t)),
                    const SizedBox(width: 32),
                  ]),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(s.running ? '没有连接' : '未连接', style: SF.t(12.5, color: SF.text3)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemExtent: 46,
                        itemBuilder: (context, i) => _row(list[i]),
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _row(Conn c) {
    final rule = c.rule.isEmpty ? 'final' : c.rule;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineSoft))),
      child: Row(children: [
        Expanded(
          flex: _cols[0],
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.host, style: SF.t(13), overflow: TextOverflow.ellipsis),
            Text(c.process, style: SF.t(11.5, color: SF.text3), overflow: TextOverflow.ellipsis),
          ]),
        ),
        Expanded(
          flex: _cols[1],
          child: Row(children: [
            Dot(_dot(c)),
            const SizedBox(width: 8),
            Expanded(child: Tooltip(message: '$rule ${c.rulePayload}', child: Text(rule, style: SF.t(13, color: SF.text2), overflow: TextOverflow.ellipsis))),
          ]),
        ),
        Expanded(flex: _cols[2], child: Text(c.chains.reversed.map(displayName).join(' → '), style: SF.t(13), overflow: TextOverflow.ellipsis)),
        Expanded(flex: _cols[3], child: Text('↑ ${fmtBytes(c.up)}  ↓ ${fmtBytes(c.down)}', style: SF.m(12, color: SF.text2), overflow: TextOverflow.ellipsis)),
        Expanded(flex: _cols[4], child: Text(fmtDuration(DateTime.now().difference(c.start)), style: SF.m(12, color: SF.text3))),
        SizedBox(
          width: 32,
          child: _tab == 0
              ? SFIconButton(Icons.close_rounded, tooltip: '关闭此连接', size: 28, iconSize: 13, bordered: false, onTap: () => AppState.I.closeConnection(c.id))
              : null,
        ),
      ]),
    );
  }
}
