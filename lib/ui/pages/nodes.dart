import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../core/profiles.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';

const _regions = <(String, List<String>)>[
  ('HK', ['香港', 'hong kong', 'hongkong', '🇭🇰', 'hk']),
  ('TW', ['台湾', '台灣', 'taiwan', '🇹🇼', 'tw']),
  ('JP', ['日本', '东京', '大阪', 'japan', 'tokyo', '🇯🇵', 'jp']),
  ('SG', ['新加坡', '狮城', 'singapore', '🇸🇬', 'sg']),
  ('US', ['美国', '洛杉矶', '圣何塞', '纽约', 'united states', 'america', '🇺🇸', 'us']),
  ('KR', ['韩国', '首尔', 'korea', '🇰🇷', 'kr']),
  ('GB', ['英国', '伦敦', 'united kingdom', 'london', '🇬🇧', 'uk']),
  ('DE', ['德国', 'germany', '🇩🇪', 'de']),
  ('FR', ['法国', 'france', '🇫🇷', 'fr']),
  ('NL', ['荷兰', 'netherlands', '🇳🇱', 'nl']),
  ('CA', ['加拿大', 'canada', '🇨🇦', 'ca']),
  ('AU', ['澳大利亚', '澳洲', 'australia', '🇦🇺', 'au']),
  ('IN', ['印度', 'india', '🇮🇳']),
  ('RU', ['俄罗斯', 'russia', '🇷🇺', 'ru']),
  ('TR', ['土耳其', 'turkey', '🇹🇷', 'tr']),
  ('MY', ['马来西亚', 'malaysia', '🇲🇾']),
  ('TH', ['泰国', 'thailand', '🇹🇭']),
  ('VN', ['越南', 'vietnam', '🇻🇳']),
  ('PH', ['菲律宾', 'philippines', '🇵🇭']),
  ('AR', ['阿根廷', 'argentina', '🇦🇷']),
  ('BR', ['巴西', 'brazil', '🇧🇷']),
  ('CN', ['中国', '回国', 'china', '🇨🇳', 'cn']),
];

String regionOf(String name) {
  final flag = splitFlag(name).$1;
  if (flag != null) return flag;
  final n = name.toLowerCase();
  for (final (code, keys) in _regions) {
    for (final k in keys) {
      if (k.length <= 2 && RegExp(r'^[a-z]{2}$').hasMatch(k)) {
        if (RegExp('(^|[^a-z])$k([^a-z]|\$)').hasMatch(n)) return code;
      } else if (n.contains(k)) {
        return code;
      }
    }
  }
  return '··';
}

String groupDesc(String type) => switch (type) {
      'Selector' => '手动选择出口节点',
      'URLTest' => '定时测速，自动选用延迟最低的节点',
      'Fallback' => '按顺序使用第一个可用节点',
      'LoadBalance' => '负载均衡',
      _ => type,
    };

class NodesPage extends StatefulWidget {
  const NodesPage({super.key});

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  String? _group;
  String _q = '';
  bool _sort = false, _testing = false, _updating = false;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final groups = s.groups;
    final g = groups.where((x) => x.name == _group).firstOrNull ?? groups.firstOrNull;
    final p = s.active;
    var members = g?.all ?? const <String>[];
    if (_q.isNotEmpty) members = members.where((m) => m.toLowerCase().contains(_q.toLowerCase())).toList();
    if (_sort) {
      members = [...members]..sort((a, b) {
          int k(String n) {
            final d = s.nodes[n]?.delay;
            return d == null ? 99999 : (d <= 0 ? 999999 : d);
          }

          return k(a).compareTo(k(b));
        });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          '代理节点',
          subtitle: Text(p == null ? '' : '${p.name} · ${fmtAgo(p.updatedAt)}更新'),
          actions: [
            SFInput(icon: Icons.search_rounded, hint: '搜索节点', width: 220, onChanged: (v) => setState(() => _q = v)),
            if (p?.kind == ProfileKind.cloud)
              SFIconButton(_updating ? Icons.hourglass_empty_rounded : Icons.refresh_rounded, tooltip: '更新订阅', onTap: _updating ? null : () => _update(p!)),
            SFButton(_testing ? '测速中…' : '延迟测试', kind: BtnKind.primary, onTap: g == null || _testing ? null : () => _test(g.all)),
          ],
        ),
        const SizedBox(height: 18),
        if (!s.running)
          Expanded(
            child: EmptyHint(
              s.status == CoreStatus.starting ? '正在连接…' : '连接后显示代理组和节点',
              action: s.status == CoreStatus.stopped ? SFButton('连接', kind: BtnKind.primary, onTap: s.start) : null,
            ),
          )
        else if (groups.isEmpty)
          const Expanded(child: EmptyHint('当前配置没有 selector / urltest 代理组', icon: Icons.hub_outlined))
        else ...[
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final x in groups)
                  Tap(
                    radius: 0,
                    onTap: () => setState(() => _group = x.name),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 150),
                      height: 58,
                      padding: const EdgeInsets.only(left: 2, right: 20),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x == g ? SF.text : Colors.transparent, width: 1.5))),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.name, style: SF.t(14, color: x == g ? SF.text : SF.text3, weight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('${x.type} · ${displayName(x.now)}', style: SF.t(12, color: SF.text3)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 28,
            child: Row(children: [
              OutlineTag(g!.type),
              const SizedBox(width: 10),
              Text(groupDesc(g.type), style: SF.t(12.5, color: SF.text2)),
              Text('  · ${g.all.length} 个节点', style: SF.t(12.5, color: SF.text3)),
              const Spacer(),
              Tap(
                onTap: () => setState(() => _sort = !_sort),
                child: Row(children: [
                  Text(_sort ? '按延迟排序' : '按配置顺序', style: SF.t(12.5, color: SF.text2)),
                  const SizedBox(width: 6),
                  const Icon(Icons.swap_vert_rounded, size: 14, color: SF.text2),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 64, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: members.length,
              itemBuilder: (context, i) => _NodeCard(name: members[i], group: g),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _test(List<String> names) async {
    setState(() => _testing = true);
    await AppState.I.testDelay(names);
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _update(Profile p) async {
    setState(() => _updating = true);
    try {
      await AppState.I.updateProfile(p);
      if (mounted) toast(context, '订阅已更新');
    } catch (e) {
      if (mounted) toast(context, '更新失败：$e', error: true);
    }
    if (mounted) setState(() => _updating = false);
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.name, required this.group});
  final String name;
  final ProxyGroup group;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final n = s.nodes[name];
    final sel = group.now == name;
    final isGroup = s.groups.any((x) => x.name == name);
    final d = n?.delay;
    return Tooltip(
      message: [
        if (group.type != 'Selector') '${group.type} 组由内核自动选择',
        if ((s.nodeTags[name] ?? const []).isNotEmpty) s.nodeTags[name]!.join(' · '),
      ].join('\n'),
      waitDuration: const Duration(seconds: 1),
      child: Tap(
        radius: 12,
        onTap: group.type == 'Selector' ? () => s.select(group, name) : null,
        child: AnimatedContainer(
          duration: SF.medium,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sel ? SF.accent.withValues(alpha: .07) : SF.surface,
            border: Border.all(color: sel ? SF.accent.withValues(alpha: .6) : SF.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: SF.medium,
              width: 34,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? SF.accent.withValues(alpha: .12) : null,
                border: Border.all(color: sel ? SF.accent.withValues(alpha: .5) : SF.input),
                borderRadius: BorderRadius.circular(5),
              ),
              child: isGroup
                  ? Icon(Icons.hub_outlined, size: 13, color: sel ? SF.accent : SF.text2)
                  : _Flag(regionOf(name), sel: sel),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(displayName(name), style: SF.t(13.5, color: sel ? SF.accentText : SF.text, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // Type and tags share one 18 px line, centred on the same axis.
                SizedBox(
                  height: _Feature.height,
                  child: Row(children: [
                    Text(n?.type ?? '', style: SF.m(12.5, color: SF.text3, height: 1)),
                    const SizedBox(width: 7),
                    // Whole tags only; any that do not fit wrap out of view.
                    Expanded(
                      child: ClipRect(
                        child: Wrap(spacing: 5, runSpacing: 4, children: [for (final f in s.nodeTags[name] ?? const <String>[]) _Feature(f, sel)]),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            Tooltip(
              message: '测速',
              child: Tap(
                radius: 6,
                onTap: () => s.testDelay([name]),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    Dot(d == null ? SF.faint : SF.latency(d)),
                    const SizedBox(width: 6),
                    Text(d == null ? '—' : (d > 0 ? '$d ms' : '超时'), style: SF.m(12.5)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.text, this.sel);
  final String text;
  final bool sel;

  static const height = 18.0;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: SF.fast,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: sel ? SF.accent.withValues(alpha: .08) : SF.raised,
          border: Border.all(color: sel ? SF.accent.withValues(alpha: .35) : SF.input),
          borderRadius: BorderRadius.circular(4),
        ),
        // widthFactor keeps the tag as narrow as its text.
        child: Center(widthFactor: 1, child: Text(text, maxLines: 1, style: SF.m(10.5, color: sel ? SF.accentText : SF.text2, height: 1))),
      );
}

/// Windows has no flag glyphs, so the country's flag is drawn as an image;
/// unknown regions fall back to the two-letter code.
class _Flag extends StatelessWidget {
  const _Flag(this.code, {required this.sel});
  final String code;
  final bool sel;

  @override
  Widget build(BuildContext context) {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
      return Text(code, style: SF.m(11, color: sel ? SF.accent : SF.text2, weight: FontWeight.w500));
    }
    return CountryFlag.fromCountryCode(code, theme: const ImageTheme(width: 22, height: 15, shape: RoundedRectangle(2)));
  }
}
