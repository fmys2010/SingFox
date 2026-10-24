import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/profiles.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../dialogs/market_dialog.dart';
import '../widgets.dart';

/// A rule as shown in the table.
class _RuleRow {
  _RuleRow(this.index, this.rule, {this.market = false});
  final int index;
  final Map<String, dynamic> rule;
  final bool market;

  static const _meta = {'outbound', 'action', 'invert', 'type', 'mode', 'rules', 'server', 'method', 'no_drop', 'sniffer', 'timeout'};

  (String, String) get condition {
    if (rule['type'] == 'logical') return ('logical', '${rule['mode'] ?? 'and'} · ${(rule['rules'] as List?)?.length ?? 0} 条子规则');
    for (final e in rule.entries) {
      if (_meta.contains(e.key)) continue;
      final v = e.value is List ? (e.value as List).join(', ') : '${e.value}';
      return (e.key, v);
    }
    return ('—', '所有流量');
  }

  String get outbound {
    final a = rule['action'] as String?;
    return switch (a) {
      'reject' => '拦截',
      'hijack-dns' => 'DNS 劫持',
      'sniff' => '协议嗅探',
      'resolve' => '解析域名',
      'route-options' => '路由选项',
      _ => rule['outbound'] as String? ?? a ?? '—',
    };
  }

  /// Approximate hit count: the core reports the matched rule as text.
  int hits(Map<String, int> all) {
    final (k, v) = condition;
    final first = v.split(', ').first;
    var n = 0;
    all.forEach((rule, c) {
      if (rule.contains(k) && rule.contains(first)) n += c;
    });
    return n;
  }
}

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  Map<String, dynamic>? _cfg;
  String? _error, _loadedFor;
  String _q = '';

  Future<void> _load() async {
    final p = AppState.I.active;
    _loadedFor = '${p?.id}:${p?.updatedAt}';
    if (p == null) return setState(() => _cfg = null);
    try {
      _cfg = jsonDecode(await AppState.I.profiles.read(p)) as Map<String, dynamic>;
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = s.active;
    if (_loadedFor != '${p?.id}:${p?.updatedAt}') {
      Future.microtask(_load);
    }
    final route = (_cfg?['route'] as Map?)?.cast<String, dynamic>() ?? {};
    final own = [for (final (i, r) in ((route['rules'] as List?) ?? []).indexed) _RuleRow(i, Map<String, dynamic>.from(r as Map))];
    final market = [for (final (i, r) in (p?.extras.rules ?? const []).indexed) _RuleRow(i, r, market: true)];
    var rows = [...market, ...own];
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      rows = rows.where((r) => jsonEncode(r.rule).toLowerCase().contains(q)).toList();
    }
    final sets = [
      for (final r in ((route['rule_set'] as List?) ?? [])) (Map<String, dynamic>.from(r as Map), false),
      for (final r in (p?.extras.ruleSets ?? const <Map<String, dynamic>>[])) (r, true),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          '规则',
          subtitle: const Text('自上而下匹配，命中即停止'),
          actions: [
            SFInput(icon: Icons.search_rounded, hint: '搜索规则', width: 220, onChanged: (v) => setState(() => _q = v)),
            SFButton('规则集市场', icon: Icons.storefront_outlined, onTap: p == null ? null : () => MarketDialog.open(context, p, _cfg)),
          ],
        ),
        const SizedBox(height: 16),
        UnderlineTabs(items: [('路由规则', '${own.length + market.length}')], index: 0, onChanged: (_) {}),
        const SizedBox(height: 16),
        if (p == null)
          const Expanded(child: EmptyHint('还没有配置', icon: Icons.sort_rounded))
        else if (_error != null)
          Expanded(child: EmptyHint('读取配置失败：$_error', icon: Icons.error_outline_rounded))
        else
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _table(p, rows, route['final'] as String?)),
              const SizedBox(width: 16),
              SizedBox(width: 280, child: _sets(p, sets)),
            ]),
          ),
      ]),
    );
  }

  static const _flex = [1, 5, 8, 4, 3];

  Widget _table(Profile p, List<_RuleRow> rows, String? fin) {
    final s = AppState.I;
    Widget header() => Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
          child: DefaultTextStyle(
            style: SF.t(12, color: SF.text3),
            child: Row(children: [
              for (final (i, t) in ['#', '类型', '匹配内容', '出站', '命中'].indexed)
                Expanded(flex: _flex[i], child: Text(t, textAlign: i == 4 ? TextAlign.right : TextAlign.left)),
              const SizedBox(width: 46),
            ]),
          ),
        );

    Widget row(_RuleRow r) {
      final on = r.market || !p.extras.disabledRules.contains(r.index);
      final (k, v) = r.condition;
      final out = r.outbound;
      final color = out == '拦截' ? SF.bad : (out.toLowerCase() == 'direct' || out == '直连' ? const Color(0xFF71717A) : (r.rule['action'] != null && r.rule['outbound'] == null ? SF.text2 : SF.accent));
      return Opacity(
        opacity: on ? 1 : .45,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineSoft))),
          child: Row(children: [
            Expanded(flex: _flex[0], child: Text(r.market ? '市' : '${r.index + 1}', style: SF.m(12, color: r.market ? SF.accent : SF.text3))),
            Expanded(flex: _flex[1], child: Align(alignment: Alignment.centerLeft, child: OutlineTag(k))),
            Expanded(flex: _flex[2], child: Tooltip(message: v, waitDuration: const Duration(milliseconds: 600), child: Text(v, style: SF.m(12.5), overflow: TextOverflow.ellipsis))),
            Expanded(
              flex: _flex[3],
              child: Row(children: [Dot(color), const SizedBox(width: 8), Expanded(child: Text(out, style: SF.t(13), overflow: TextOverflow.ellipsis))]),
            ),
            Expanded(flex: _flex[4], child: Text('${r.hits(s.ruleHits)}', textAlign: TextAlign.right, style: SF.m(12, color: SF.text2))),
            const SizedBox(width: 16),
            SizedBox(
              width: 30,
              child: r.market
                  ? SFIconButton(Icons.delete_outline_rounded, tooltip: '移除', size: 26, iconSize: 14, bordered: false, onTap: () => _removeMarketRule(p, r.index))
                  : SFSwitch(small: true, value: on, onChanged: (v) => _toggle(p, r.index, v)),
            ),
          ]),
        ),
      );
    }

    return SFCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        header(),
        Expanded(child: ListView(children: [for (final r in rows) row(r)])),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(color: Color(0xFF0E0E10), border: Border(top: BorderSide(color: SF.line))),
          child: Row(children: [
            Expanded(flex: _flex[0], child: Text('—', style: SF.m(12, color: SF.text3))),
            Expanded(flex: _flex[1], child: const Align(alignment: Alignment.centerLeft, child: OutlineTag('final'))),
            Expanded(flex: _flex[2], child: Text('未命中任何规则时', style: SF.t(13, color: SF.text3))),
            Expanded(flex: _flex[3], child: Row(children: [const Dot(SF.accent), const SizedBox(width: 8), Text(fin ?? '第一个出站', style: SF.t(13))])),
            Expanded(flex: _flex[4], child: Text('${(s.ruleHits['final'] ?? 0) + (s.ruleHits[''] ?? 0)}', textAlign: TextAlign.right, style: SF.m(12, color: SF.text2))),
            const SizedBox(width: 46),
          ]),
        ),
      ]),
    );
  }

  Widget _sets(Profile p, List<(Map<String, dynamic>, bool)> sets) => SFCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 26, child: Row(children: [Text('规则集', style: SF.t(13.5, weight: FontWeight.w600)), const Spacer(), Text('${sets.length}', style: SF.m(12, color: SF.text3))])),
          const SizedBox(height: 6),
          Expanded(
            child: sets.isEmpty
                ? Center(child: Text('没有规则集，可以从市场添加', style: SF.t(12.5, color: SF.text3)))
                : ListView(children: [
                    for (final (r, fromMarket) in sets)
                      Container(
                        height: 50,
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineInner))),
                        child: Row(children: [
                          Expanded(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r['tag']}', style: SF.m(12.5), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text(fromMarket ? '市场 · remote' : '${r['type'] ?? 'remote'} · ${r['format'] ?? 'binary'}', style: SF.t(11.5, color: SF.text3)),
                            ]),
                          ),
                          if (fromMarket)
                            SFIconButton(Icons.delete_outline_rounded, tooltip: '移除', size: 26, iconSize: 14, bordered: false, onTap: () => _removeSet(p, r['tag'])),
                        ]),
                      ),
                  ]),
          ),
        ]),
      );

  Future<void> _toggle(Profile p, int i, bool on) async {
    on ? p.extras.disabledRules.remove(i) : p.extras.disabledRules.add(i);
    setState(() {});
    await AppState.I.saveProfile(p);
  }

  Future<void> _removeMarketRule(Profile p, int i) async {
    p.extras.rules.removeAt(i);
    setState(() {});
    await AppState.I.saveProfile(p);
  }

  Future<void> _removeSet(Profile p, String tag) async {
    p.extras.ruleSets.removeWhere((r) => r['tag'] == tag);
    for (final r in p.extras.rules) {
      (r['rule_set'] as List?)?.remove(tag);
    }
    p.extras.rules.removeWhere((r) => (r['rule_set'] as List?)?.isEmpty ?? false);
    setState(() {});
    await AppState.I.saveProfile(p);
  }
}
