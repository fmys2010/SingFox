import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/profiles.dart';
import '../core/updater.dart';
import '../core/site_test.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../ui/pages/nodes.dart' show regionOf, groupDesc;
import '../ui/pages/overview.dart' show PlanetMark, currentNode;
import '../ui/widgets.dart';
import 'mobile_widgets.dart';

String profileMeta(Profile p) {
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

Widget _flag(String code, {double w = 36, double h = 24}) {
  if (RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
    return CountryFlag.fromCountryCode(code, theme: ImageTheme(width: w, height: h, shape: const RoundedRectangle(3)));
  }
  return Container(
    width: w,
    height: h,
    alignment: Alignment.center,
    decoration: BoxDecoration(border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(3)),
    child: Text('··', style: SF.m(11, color: SF.text3)),
  );
}

// ======================================================================= overview

class MOverviewPage extends StatelessWidget {
  const MOverviewPage({super.key, required this.onProfiles, required this.onGo});
  final VoidCallback onProfiles;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final p = s.active;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // profile chip
        GestureDetector(
          onTap: onProfiles,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: SF.surface, border: Border.all(color: SF.line), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _Avatar(p?.initial ?? '+'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p?.name ?? '还没有配置', style: SF.t(14.5, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(p == null ? '点击增加配置' : profileMeta(p), style: SF.t(12, color: SF.text3), overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.unfold_more_rounded, size: 18, color: SF.text3),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        MSegmented<String>(options: const [('rule', '规则'), ('global', '全局'), ('direct', '直连')], value: s.settings.mode, onChanged: s.setMode),
        const SizedBox(height: 12),
        _Hero(onGo: onGo),
        const SizedBox(height: 12),
        _statGrid(s),
        const SizedBox(height: 12),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MRow('局域网共享', sub: '允许其他设备连接', last: true, trailing: MSwitch(value: s.settings.allowLan, onChanged: (v) => s.updateSettings((x) => x.allowLan = v))),
        ),
        const SizedBox(height: 12),
        _ExitIpCard(),
        const SizedBox(height: 12),
        _Outbounds(),
        const SizedBox(height: 12),
        _Sites(),
      ],
    );
  }

  Widget _statGrid(AppState s) {
    final tcp = s.conns.where((c) => c.meta['network'] == 'tcp').length;
    final udp = s.conns.where((c) => c.meta['network'] == 'udp').length;
    final total = fmtBytes(s.upTotal + s.downTotal).split(' ');
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: [
        _Stat('下载', fmtRate(s.down), '峰值 ${fmtRate(s.downPeak).$1}', s.downHist, SF.accent),
        _Stat('上传', fmtRate(s.up), '峰值 ${fmtRate(s.upPeak).$1}', s.upHist, const Color(0xFF71717A)),
        _Stat('活动连接', ('${s.conns.length}', ''), 'TCP $tcp · UDP $udp', s.connHist, SF.ok),
        _Stat('本次流量', (total[0], total[1]), '↑ ${fmtBytes(s.upTotal)}', null, SF.accent),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.letter);
  final String letter;
  static const size = 34.0;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF222226), borderRadius: BorderRadius.circular(size / 4)),
        child: Text(letter, style: SF.t(size * .43, weight: FontWeight.w600)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.note, this.hist, this.color);
  final String label, note;
  final (String, String) value;
  final List<int>? hist;
  final Color color;

  @override
  Widget build(BuildContext context) => MCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(label, style: SF.t(12, color: SF.text3)),
            const SizedBox(width: 6),
            Expanded(child: Text(note, textAlign: TextAlign.right, style: SF.t(11.5, color: SF.text3), overflow: TextOverflow.ellipsis)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(value.$1, style: SF.m(22, weight: FontWeight.w500)))),
            if (value.$2.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 3, bottom: 3), child: Text(value.$2, style: SF.t(11.5, color: SF.text3))),
            const Spacer(),
            if (hist != null) Spark(hist!, color),
          ]),
        ]),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onGo});
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final (node, group) = currentNode(s);
    final n = s.nodes[node];
    final busy = s.status == CoreStatus.starting || s.status == CoreStatus.stopping;
    final statusColor = s.running ? SF.ok : (s.error != null ? SF.bad : SF.text3);
    return MCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      child: Column(children: [
        Semantics(
          button: true,
          label: s.running ? '断开' : '连接',
          child: Tap(
            radius: 52,
            onTap: busy ? null : s.toggle,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: SF.raised,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2E2E33)),
                boxShadow: s.running ? [BoxShadow(color: SF.accent.withValues(alpha: .08), spreadRadius: 8)] : null,
              ),
              child: Transform.scale(scale: 1.35, child: PlanetMark(on: s.status == CoreStatus.running || s.status == CoreStatus.starting, lit: s.running)),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Dot(s.running ? SF.ok : (s.error != null ? SF.bad : SF.faint), halo: s.running),
          const SizedBox(width: 8),
          Text(
            switch (s.status) {
              CoreStatus.running => '已连接',
              CoreStatus.starting => '正在连接…',
              CoreStatus.stopping => '正在断开…',
              CoreStatus.stopped => s.error != null ? '连接失败' : '未连接',
            },
            style: SF.t(13, color: statusColor, weight: FontWeight.w500),
          ),
          if (s.startedAt != null) ...[const SizedBox(width: 8), Text(fmtDuration(DateTime.now().difference(s.startedAt!)), style: SF.m(13, color: SF.text3))],
        ]),
        const SizedBox(height: 10),
        Text(
          s.running ? (node.isEmpty ? '直连' : displayName(node)) : (s.active?.name ?? '还没有配置'),
          style: SF.t(28, weight: FontWeight.w600, height: 1.15),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        if (s.error != null && !s.running)
          Text(s.error!, style: SF.t(12.5, color: SF.bad), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis)
        else
          DefaultTextStyle(
            style: SF.t(12.5, color: SF.text3),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
              if (n != null && n.type.isNotEmpty) Text(n.type),
              if (s.running)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: '延迟 '),
                  TextSpan(
                    text: n?.delay == null ? '—' : (n!.delay! > 0 ? '${n.delay} ms' : '超时'),
                    style: SF.m(12.5, color: n?.delay == null ? SF.text3 : SF.latency(n!.delay)),
                  ),
                ])),
              Text(s.running ? '策略组 · ${group?.name ?? '—'}' : '点击上方按钮连接'),
            ]),
          ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: MButton('切换节点', kind: MBtn.primary, onTap: () => onGo(1))),
          const SizedBox(width: 10),
          Expanded(child: MButton('延迟测试', onTap: s.running && node.isNotEmpty ? () => s.testDelay([node]) : null)),
        ]),
      ]),
    );
  }
}

Color _riskColor(int? r) => r == null ? SF.faint : (r < 25 ? SF.ok : (r < 60 ? SF.warn : SF.bad));

class _ExitIpCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final ip = s.exitIp;
    Widget kv(String k, Widget v, {bool last = false}) => Container(
          height: 42,
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: SF.lineInner))),
          child: Row(children: [
            Text(k, style: SF.t(13, color: SF.text3)),
            const SizedBox(width: 12),
            Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
          ]),
        );
    return MCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('出口 IP', style: SF.t(14, weight: FontWeight.w600)),
          const Spacer(),
          Flexible(
            child: Text(
              s.exitIpLoading ? '检测中…' : (ip != null ? '检测于 ${fmtAgo(ip.checkedAt)}' : (s.exitIpError ?? (s.running ? '' : '连接后自动检测'))),
              style: SF.t(12, color: s.exitIpError != null ? SF.bad : SF.text3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Tap(
            onTap: s.running && !s.exitIpLoading ? s.checkExitIp : null,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.refresh_rounded, size: 18, color: s.running ? SF.text2 : SF.faint)),
          ),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.lineInner))),
          child: Row(children: [
            _flag(ip?.countryCode ?? ''),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ip?.country ?? '—', style: SF.t(15, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(ip == null ? '未检测' : ip.countryCode, style: SF.t(12, color: SF.text3)),
              ]),
            ),
          ]),
        ),
        kv('地理位置', Text(ip?.location ?? '—', style: SF.t(13), overflow: TextOverflow.ellipsis)),
        kv(
          'IP',
          GestureDetector(
            onTap: ip == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: ip.ip));
                    mtoast(context, '已复制 ${ip.ip}');
                  },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(ip?.ip ?? '—', style: SF.m(13), overflow: TextOverflow.ellipsis)),
              if (ip != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy_rounded, size: 14, color: SF.text3)),
            ]),
          ),
        ),
        kv(
          '运营商',
          Text.rich(
            TextSpan(children: [
              TextSpan(text: ip?.isp ?? '—', style: SF.t(13)),
              if (ip != null) TextSpan(text: '  ${ip.asn}', style: SF.m(12, color: SF.text3)),
            ]),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
          last: true,
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('风险度评分', style: SF.t(13, color: SF.text3)),
          const Spacer(),
          Text(ip?.risk == null ? '—' : '${ip!.risk}', style: SF.m(22, weight: FontWeight.w500)),
          Text(' / 100', style: SF.m(12, color: SF.text3)),
        ]),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: (ip?.risk ?? 0) / 100, minHeight: 4, backgroundColor: const Color(0xFF222226), color: _riskColor(ip?.risk)),
        ),
        if (ip != null) ...[
          const SizedBox(height: 9),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: _riskColor(ip.risk).withValues(alpha: .12), borderRadius: BorderRadius.circular(5)),
              child: Text(ip.riskLabel, style: SF.t(12, color: _riskColor(ip.risk), weight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('${ip.ipType} · ${ip.flags.join(' · ')}', style: SF.t(12, color: SF.text3), overflow: TextOverflow.ellipsis)),
          ]),
        ],
      ]),
    );
  }
}

class _Outbounds extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final share = s.outboundShare.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = share.fold<int>(0, (a, e) => a + e.value);
    const colors = [SF.accent, SF.text2, Color(0xFF52525B), Color(0xFF3F3F46)];
    return MCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Text('出站分布', style: SF.t(14, weight: FontWeight.w600)), const Spacer(), Text('本次运行', style: SF.t(12, color: SF.text3))]),
        const SizedBox(height: 14),
        if (share.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: Text(s.running ? '还没有流量' : '未连接', style: SF.t(12.5, color: SF.text3))))
        else
          for (var i = 0; i < share.length && i < 6; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == share.length - 1 || i == 5 ? 0 : 16),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(displayName(share[i].key), style: SF.t(13), overflow: TextOverflow.ellipsis)),
                  Text(fmtBytes(share[i].value), style: SF.m(12, color: SF.text3)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: share[i].value / total,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF222226),
                    color: share[i].key.toLowerCase().contains('block') || share[i].key.contains('拦截') ? SF.bad : colors[i < 3 ? i : 3],
                  ),
                ),
              ]),
            ),
      ]),
    );
  }
}

class _Sites extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return MCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(children: [
        Row(children: [
          Text('网站测速', style: SF.t(14, weight: FontWeight.w600)),
          const Spacer(),
          if (s.sitesTesting)
            const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: SF.text3)))
          else
            Tap(onTap: s.running ? s.testSites : null, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.refresh_rounded, size: 18, color: s.running ? SF.text2 : SF.faint))),
        ]),
        const SizedBox(height: 4),
        for (var r = 0; r < 3; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SiteTag(Site.all[r * 2])),
            const SizedBox(width: 8),
            Expanded(child: _SiteTag(Site.all[r * 2 + 1])),
          ]),
        ],
      ]),
    );
  }
}

class _SiteTag extends StatelessWidget {
  const _SiteTag(this.site);
  final Site site;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final ms = s.siteDelay[site.name];
    final measuring = s.siteDelay.containsKey(site.name) && ms == null;
    final (text, color) = switch (ms) {
      null => (measuring ? '…' : '—', SF.faint),
      < 0 => ('超时', SF.bad),
      _ => ('$ms', SF.latency(ms)),
    };
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 8, right: 10),
      decoration: BoxDecoration(
        color: site.color.withValues(alpha: .07),
        border: Border.all(color: site.color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset(site.icon, width: 16, height: 16, filterQuality: FilterQuality.medium)),
        const SizedBox(width: 8),
        Expanded(child: Text(site.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SF.t(12.5, color: site.color))),
        Text(text, style: SF.m(12, color: color)),
      ]),
    );
  }
}

// ======================================================================= nodes

class MNodesPage extends StatefulWidget {
  const MNodesPage({super.key});

  @override
  State<MNodesPage> createState() => _MNodesPageState();
}

class _MNodesPageState extends State<MNodesPage> {
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
      int k(String n) {
        final d = s.nodes[n]?.delay;
        return d == null ? 99999 : (d <= 0 ? 999999 : d);
      }

      members = [...members]..sort((a, b) => k(a).compareTo(k(b)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MHeader('代理节点', actions: [
            if (p?.kind == ProfileKind.cloud) MIconButton(_updating ? Icons.hourglass_empty_rounded : Icons.refresh_rounded, label: '更新订阅', onTap: _updating ? null : () => _update(p!)),
            MButton(_testing ? '测速中…' : '延迟测试', kind: MBtn.primary, height: 44, onTap: g == null || _testing ? null : () => _test(g.all)),
          ]),
          Padding(padding: const EdgeInsets.only(top: 2, bottom: 10), child: Text(p == null ? '' : '${p.name} · ${fmtAgo(p.updatedAt)}更新', style: SF.t(12.5, color: SF.text3))),
          MSearch(hint: '搜索节点', onChanged: (v) => setState(() => _q = v)),
        ]),
      ),
      if (!s.running)
        Expanded(
          child: EmptyHint(
            s.status == CoreStatus.starting ? '正在连接…' : '连接后显示代理组和节点',
            action: s.status == CoreStatus.stopped ? MButton('连接', kind: MBtn.primary, onTap: s.start) : null,
          ),
        )
      else if (groups.isEmpty)
        const Expanded(child: EmptyHint('当前配置没有 selector / urltest 代理组', icon: Icons.hub_outlined))
      else ...[
        Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final x in groups)
                GestureDetector(
                  onTap: () => setState(() => _group = x.name),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 56,
                    margin: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x == g ? SF.text : Colors.transparent, width: 1.5))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.name, style: SF.t(14, color: x == g ? SF.text : SF.text3, weight: FontWeight.w500)),
                      const SizedBox(height: 3),
                      Text('${x.type} · ${displayName(x.now)}', style: SF.t(12, color: SF.text3)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            OutlineTag(g!.type),
            const SizedBox(width: 8),
            Expanded(child: Text('${groupDesc(g.type)} · ${g.all.length} 个', style: SF.t(12.5, color: SF.text2), overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => setState(() => _sort = !_sort),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  Text(_sort ? '按延迟' : '按配置', style: SF.t(12.5, color: SF.text2)),
                  const SizedBox(width: 4),
                  const Icon(Icons.swap_vert_rounded, size: 15, color: SF.text2),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _NodeCard(name: members[i], group: g),
          ),
        ),
      ],
    ]);
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
      if (mounted) mtoast(context, '订阅已更新');
    } catch (e) {
      if (mounted) mtoast(context, '更新失败：$e', error: true);
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
    final tags = s.nodeTags[name] ?? const <String>[];
    return Tap(
      radius: 12,
      onTap: group.type == 'Selector'
          ? () => s.select(group, name)
          : () => mtoast(context, '${group.type} 组由内核自动选择'),
      child: AnimatedContainer(
        duration: SF.medium,
        curve: Curves.easeOutCubic,
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: sel ? SF.accent.withValues(alpha: .07) : SF.surface,
          border: Border.all(color: sel ? SF.accent.withValues(alpha: .6) : SF.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          isGroup
              ? Container(
                  width: 36,
                  height: 24,
                  decoration: BoxDecoration(border: Border.all(color: sel ? SF.accent : SF.input), borderRadius: BorderRadius.circular(5)),
                  child: Icon(Icons.hub_outlined, size: 14, color: sel ? SF.accent : SF.text2),
                )
              : _flag(regionOf(name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayName(name), style: SF.t(14.5, color: sel ? SF.accentText : SF.text, weight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              SizedBox(
                height: 18,
                child: Row(children: [
                  Text(n?.type ?? '', style: SF.m(12, color: SF.text3, height: 1)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: ClipRect(
                      child: Wrap(spacing: 5, runSpacing: 4, children: [
                        for (final f in tags)
                          Container(
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(border: Border.all(color: sel ? SF.accent.withValues(alpha: .35) : SF.input), borderRadius: BorderRadius.circular(4)),
                            child: Text(f, style: SF.t(11, color: sel ? SF.accentText : SF.text2, height: 1)),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => s.testDelay([name]),
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
              alignment: Alignment.centerRight,
              child: Text(
                d == null ? '测速' : (d > 0 ? '$d' : '超时'),
                style: d == null ? SF.t(12.5, color: SF.text3) : SF.m(14, color: SF.latency(d)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================= connections + logs

class MConnectionsPage extends StatefulWidget {
  const MConnectionsPage({super.key});

  @override
  State<MConnectionsPage> createState() => _MConnectionsPageState();
}

class _MConnectionsPageState extends State<MConnectionsPage> {
  int _tab = 0;
  String _q = '';

  Color _tint(Conn c) {
    final out = c.chains.isEmpty ? '' : c.chains.first.toLowerCase();
    final rule = c.rule.toLowerCase();
    if (rule.contains('reject') || out.contains('block') || out.contains('reject')) return SF.bad;
    if (out == 'direct' || rule.contains('direct')) return SF.text3;
    return SF.accentText;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    var list = _tab == 0 ? s.conns : s.closed.toList();
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list.where((c) => c.host.toLowerCase().contains(q) || c.process.toLowerCase().contains(q) || c.rule.toLowerCase().contains(q)).toList();
    }
    final tabs = [('活动', '${s.conns.length}'), ('已关闭', '${s.closed.length}'), ('日志', null)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: MHeader('连接', actions: [MButton('全部断开', kind: MBtn.danger, onTap: s.running ? s.closeAll : null)]),
      ),
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
        child: Row(children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: () => setState(() => _tab = i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 44,
                margin: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == _tab ? SF.text : Colors.transparent, width: 1.5))),
                child: Row(children: [
                  Text(tabs[i].$1, style: SF.t(14, color: i == _tab ? SF.text : SF.text3, weight: FontWeight.w500)),
                  if (tabs[i].$2 != null) ...[const SizedBox(width: 6), Text(tabs[i].$2!, style: SF.m(11.5, color: SF.text3))],
                ]),
              ),
            ),
        ]),
      ),
      if (_tab == 2)
        const Expanded(child: _Logs())
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Expanded(child: _Rate('↓ 下载', fmtBytes(s.down))),
            const SizedBox(width: 10),
            Expanded(child: _Rate('↑ 上传', fmtBytes(s.up))),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: MSearch(hint: '搜索域名 / 进程 / 规则', onChanged: (v) => setState(() => _q = v))),
        Expanded(
          child: !s.running && list.isEmpty
              ? const EmptyHint('连接后显示连接列表')
              : list.isEmpty
                  ? Center(child: Text('没有连接', style: SF.t(13, color: SF.text3)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: list.length > 200 ? 200 : list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        final out = c.chains.isEmpty ? '直连' : c.chains.reversed.map(displayName).take(2).join(' → ');
                        return GestureDetector(
                          onLongPress: _tab == 0 ? () => s.closeConnection(c.id) : null,
                          child: MCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            radius: 12,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(child: Text(c.host, style: SF.t(14, weight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 8),
                                OutlineTag('${c.meta['network'] ?? ''}'.toUpperCase()),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Flexible(child: Text(out, style: SF.t(12, color: _tint(c)), overflow: TextOverflow.ellipsis)),
                                Text(' · ${c.rule.isEmpty ? c.process : c.rule}', style: SF.t(12, color: SF.text3)),
                                const Spacer(),
                                Text('↓ ${fmtBytes(c.down)}', style: SF.m(12, color: SF.text3)),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ],
    ]);
  }
}

class _Rate extends StatelessWidget {
  const _Rate(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => MCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 12,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: SF.t(11.5, color: SF.text3)),
          const SizedBox(height: 4),
          Text('$value/s', style: SF.m(16)),
        ]),
      );
}

class _Logs extends StatelessWidget {
  const _Logs();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final lines = s.logs.toList().reversed.take(300).toList();
    if (lines.isEmpty) return Center(child: Text('暂无日志', style: SF.t(13, color: SF.text3)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final l = lines[i];
        final lc = switch (l.level) {
          'ERROR' || 'FATAL' || 'PANIC' => SF.bad,
          'WARN' => SF.warn,
          'DEBUG' || 'TRACE' => SF.faint,
          _ => SF.text3,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${l.time}  ', style: SF.m(11.5, color: SF.faint)),
              TextSpan(text: '${l.level}  ', style: SF.m(11.5, color: lc, weight: FontWeight.w500)),
              TextSpan(text: l.module.isEmpty ? l.message : '${l.module}: ${l.message}', style: SF.m(11.5, color: SF.text2)),
            ]),
          ),
        );
      },
    );
  }
}

// ======================================================================= settings

class MSettingsPage extends StatelessWidget {
  const MSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final st = s.settings;
    Widget section(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 18, 0, 8), child: Text(t, style: SF.t(12, color: SF.text3)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const MHeader('设置'),
        section('连接'),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            MRow('启动后自动连接', sub: '打开 SingFox 时自动建立 VPN', trailing: MSwitch(value: st.autoConnect, onChanged: (v) => s.updateSettings((x) => x.autoConnect = v, restart: false))),
            MRow('统一延迟', sub: '测速时去掉握手耗时', trailing: MSwitch(value: st.unifiedDelay, onChanged: (v) => s.updateSettings((x) => x.unifiedDelay = v, restart: false))),
            MRow('混合端口', trailing: Text('${st.mixedPort}', style: SF.m(13, color: SF.text2)), last: true),
          ]),
        ),
        section('DNS'),
        MCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MSegmented<String>(
              options: const [('redirhost', '防泄漏分流'), ('profile', '使用配置')],
              value: st.dnsMode,
              onChanged: (v) => s.updateSettings((x) => x.dnsMode = v),
            ),
            const SizedBox(height: 10),
            Text(st.dnsMode == 'redirhost' ? '境外与未知域名只经代理查询，不发往本地 DNS。' : '保留配置文件自带的 dns 设置。', style: SF.t(12, color: SF.text3)),
          ]),
        ),
        section('日志'),
        MCard(
          padding: const EdgeInsets.all(16),
          child: MSegmented<String>(
            options: const [('error', '错误'), ('warn', '警告'), ('info', '信息'), ('debug', '调试')],
            value: st.logLevel,
            onChanged: (v) => s.updateSettings((x) => x.logLevel = v),
          ),
        ),
        section('关于'),
        MCard(
          child: Row(children: [
            SizedBox(width: 44, height: 44, child: CustomPaint(painter: _Mark())),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SingFox', style: SF.t(15, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${Updater.appVersion} · sing-box ${s.coreVersion.isEmpty ? '—' : s.coreVersion}', style: SF.m(12, color: SF.text3)),
              ]),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Mark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // The same parcel mark the desktop title bar paints.
    canvas.scale(size.width / 512, size.height / 512);
    void face(int c, Path p) => canvas.drawPath(p, Paint()..color = Color(c));
    face(0xFF9C4A1C, Path()..moveTo(88, 187)..lineTo(254, 300)..lineTo(254, 436)..quadraticBezierTo(247, 436, 240, 432)..lineTo(103, 341)..quadraticBezierTo(88, 331, 88, 314)..close());
    face(0xFFC25E26, Path()..moveTo(254, 300)..lineTo(422, 187)..lineTo(422, 314)..quadraticBezierTo(422, 330, 408, 340)..lineTo(266, 432)..quadraticBezierTo(260, 436, 254, 436)..close());
    face(0xFFE8834A, Path()..moveTo(88, 187)..quadraticBezierTo(87, 181, 96, 175)..lineTo(237, 79)..quadraticBezierTo(253, 69, 268, 79)..lineTo(414, 176)..quadraticBezierTo(422, 181, 422, 190)..lineTo(254, 300)..close());
    face(0xFFE8834A, Path()..moveTo(242, 292)..lineTo(266, 292)..lineTo(266, 423)..quadraticBezierTo(266, 432, 258, 436)..quadraticBezierTo(253, 438, 248, 434)..quadraticBezierTo(242, 431, 242, 423)..close());
    face(0xFFF6D7C2, Path()..moveTo(139, 145)..lineTo(173, 122)..lineTo(350, 243)..lineTo(314, 266)..close());
    face(0xFFFCEBDD, Path()..moveTo(173, 122)..lineTo(195, 107)..lineTo(373, 227)..lineTo(350, 243)..close());
    face(0xFFE2B293, Path()..moveTo(314, 266)..lineTo(350, 243)..lineTo(350, 294)..quadraticBezierTo(350, 300, 344, 304)..lineTo(330, 313)..quadraticBezierTo(323, 317, 318, 311)..quadraticBezierTo(314, 308, 314, 301)..close());
    face(0xFFF3CDB3, Path()..moveTo(350, 243)..lineTo(373, 227)..lineTo(373, 269)..quadraticBezierTo(373, 279, 364, 286)..lineTo(350, 296)..close());
  }

  @override
  bool shouldRepaint(_Mark old) => false;
}
