import 'package:flutter/material.dart';

import '../../core/profiles.dart';
import '../../core/rule_market.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

/// 规则集市场: pick rule sets from MetaCubeX/meta-rules-dat@sing.
class MarketDialog extends StatefulWidget {
  const MarketDialog({super.key, required this.profile, this.config});
  final Profile profile;
  final Map<String, dynamic>? config;

  static Future<void> open(BuildContext context, Profile p, Map<String, dynamic>? cfg) => showDialog(
        context: context,
        barrierColor: const Color(0x9E000000),
        builder: (_) => MarketDialog(profile: p, config: cfg),
      );

  @override
  State<MarketDialog> createState() => _MarketDialogState();
}

class _MarketDialogState extends State<MarketDialog> {
  List<MarketItem> _items = [];
  DateTime? _at;
  bool _loading = true;
  String? _error;
  String _cat = '全部', _q = '';
  final Set<String> _picked = {};
  bool _makeRule = true;
  late String _outbound;
  late final List<String> _outbounds;

  Set<String> get _existing => {
        for (final r in ((widget.config?['route'] as Map?)?['rule_set'] as List? ?? [])) '${(r as Map)['tag']}',
        for (final r in widget.profile.extras.ruleSets) '${r['tag']}',
      };

  @override
  void initState() {
    super.initState();
    final obs = [for (final o in (widget.config?['outbounds'] as List? ?? [])) Map<String, dynamic>.from(o as Map)];
    final groups = [for (final o in obs) if (o['type'] == 'selector' || o['type'] == 'urltest') '${o['tag']}'];
    _outbounds = [...groups, for (final o in obs) if (o['type'] == 'direct') '${o['tag']}', '拦截'];
    if (!_outbounds.contains('direct')) _outbounds.insert(groups.length, 'direct');
    _outbound = _outbounds.first;
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!refresh) {
        final (items, at) = await RuleMarket.cached();
        _items = items;
        _at = at;
      }
      if (refresh || _items.isEmpty) {
        final s = AppState.I;
        _items = await RuleMarket.refresh(proxyPort: s.running ? s.settings.mixedPort : null);
        _at = DateTime.now();
      }
    } catch (e) {
      _error = '获取列表失败：$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final p = widget.profile;
    final picked = _items.where((i) => _picked.contains(i.tag)).toList();
    final detour = _outbounds.first == 'direct' || _outbounds.first == '拦截' ? null : _outbounds.first;
    for (final i in picked) {
      p.extras.ruleSets.add({'tag': i.tag, 'url': i.url, 'detour': ?detour});
    }
    if (_makeRule && picked.isNotEmpty) {
      p.extras.rules.add({
        'rule_set': [for (final i in picked) i.tag],
        if (_outbound == '拦截') 'action': 'reject' else 'outbound': _outbound,
      });
    }
    await AppState.I.saveProfile(p);
    if (mounted) {
      Navigator.pop(context);
      toast(context, '已添加 ${picked.length} 个规则集');
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    final cats = ['全部', 'geosite', 'geoip', 'asn', 'lite-geosite', 'lite-geoip'];
    var list = _cat == '全部' ? _items : _items.where((i) => i.category == _cat).toList();
    if (_q.isNotEmpty) list = list.where((i) => i.tag.toLowerCase().contains(_q.toLowerCase())).toList();
    final n = _picked.length;
    return Dialog(
      backgroundColor: SF.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 880,
        height: 640,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('规则集市场', style: SF.t(16, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '来源 ', style: SF.t(12, color: SF.text3)),
                  TextSpan(text: '${RuleMarket.repo}@${RuleMarket.branch}', style: SF.m(12, color: SF.text2)),
                  TextSpan(text: ' · ${_at == null ? '未同步' : '同步于 ${fmtAgo(_at)}'} · ${_items.length} 个', style: SF.t(12, color: SF.text3)),
                ])),
              ]),
              const Spacer(),
              SFIconButton(Icons.refresh_rounded, tooltip: '重新同步', size: 30, onTap: _loading ? null : () => _load(refresh: true)),
              const SizedBox(width: 6),
              SFIconButton(Icons.close_rounded, tooltip: '关闭', size: 30, bordered: false, onTap: () => Navigator.pop(context)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineInner))),
            child: Row(children: [
              SFInput(icon: Icons.search_rounded, hint: '搜索规则集，如 youtube、openai', width: 300, background: SF.bg, onChanged: (v) => setState(() => _q = v)),
              const Spacer(),
              Segmented<String>(options: [for (final c in cats) (c, c)], value: _cat, onChanged: (v) => setState(() => _cat = v), mono: true, background: SF.bg),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: SF.accent)))
                : _error != null
                    ? EmptyHint(_error!, icon: Icons.cloud_off_rounded, action: SFButton('重试', onTap: () => _load(refresh: true)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        itemCount: list.length,
                        itemExtent: 44,
                        itemBuilder: (context, i) {
                          final it = list[i];
                          final added = existing.contains(it.tag);
                          final on = _picked.contains(it.tag);
                          return Tap(
                            radius: 9,
                            onTap: added ? null : () => setState(() => on ? _picked.remove(it.tag) : _picked.add(it.tag)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: on ? SF.accent.withValues(alpha: .06) : null, borderRadius: BorderRadius.circular(9)),
                              child: Row(children: [
                                SizedBox(
                                  width: 28,
                                  child: added ? null : Align(alignment: Alignment.centerLeft, child: SFCheck(on)),
                                ),
                                Expanded(flex: 4, child: Text(it.tag, style: SF.m(13, color: added ? SF.text3 : SF.text), overflow: TextOverflow.ellipsis)),
                                SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: OutlineTag(it.category))),
                                Expanded(flex: 4, child: Text(it.path, style: SF.m(11.5, color: SF.text3), overflow: TextOverflow.ellipsis)),
                                SizedBox(
                                  width: 70,
                                  child: Text(added ? '已添加' : (on ? '待添加' : ''), textAlign: TextAlign.right, style: SF.t(12, color: added ? SF.text3 : SF.accent)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            decoration: const BoxDecoration(color: Color(0xFF0E0E10), border: Border(top: BorderSide(color: SF.lineInner))),
            child: Row(children: [
              Tap(
                onTap: () => setState(() => _makeRule = !_makeRule),
                child: Row(children: [
                  SFCheck(_makeRule),
                  const SizedBox(width: 10),
                  Text('同时创建路由规则，出站', style: SF.t(12.5, color: SF.text2)),
                ]),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                color: SF.raised,
                enabled: _makeRule,
                onSelected: (v) => setState(() => _outbound = v),
                itemBuilder: (_) => [for (final o in _outbounds) PopupMenuItem(value: o, child: Text(o, style: SF.t(13)))],
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: SF.bg, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(7)),
                  child: Row(children: [Text(_outbound, style: SF.t(12.5)), const SizedBox(width: 8), const Icon(Icons.expand_more_rounded, size: 14, color: SF.text3)]),
                ),
              ),
              const Spacer(),
              SFButton('取消', onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              SFButton(n == 0 ? '添加规则集' : '添加 $n 个规则集', kind: BtnKind.primary, onTap: n == 0 ? null : _add),
            ]),
          ),
        ]),
      ),
    );
  }
}
