import 'dart:math';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/site_test.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets.dart';
import '../world_map.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.onGo});
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            '概览',
            actions: [
              Segmented<String>(options: const [('rule', '规则'), ('global', '全局'), ('direct', '直连')], value: s.settings.mode, onChanged: s.setMode),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Hero(onGo: onGo)),
                const SizedBox(width: 16),
                SizedBox(width: 288, child: _Toggles()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Stat('下载', fmtRate(s.down), '峰值 ${fmtRate(s.downPeak).$1}', s.downHist, SF.accent)),
                const SizedBox(width: 16),
                Expanded(child: _Stat('上传', fmtRate(s.up), '峰值 ${fmtRate(s.upPeak).$1}', s.upHist, const Color(0xFF71717A))),
                const SizedBox(width: 16),
                Expanded(
                  child: _Stat(
                    '活动连接',
                    ('${s.conns.length}', ''),
                    'TCP ${s.conns.where((c) => c.meta['network'] == 'tcp').length} · UDP ${s.conns.where((c) => c.meta['network'] == 'udp').length}',
                    s.connHist,
                    SF.ok,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Stat(
                    '本次流量',
                    (fmtBytes(s.upTotal + s.downTotal).split(' ')[0], fmtBytes(s.upTotal + s.downTotal).split(' ')[1]),
                    '↑ ${fmtBytes(s.upTotal)}',
                    null,
                    SF.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Not const: these read AppState and must rebuild with it.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ExitIpCard()),
                const SizedBox(width: 16),
                SizedBox(
                  width: 288,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _Outbounds()),
                      const SizedBox(height: 16),
                      // A third of the column at the default window size.
                      SizedBox(height: 112, child: _Sites()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Follows selector chains to the leaf node actually in use.
(String, ProxyGroup?) currentNode(AppState s) {
  if (s.groups.isEmpty) return ('', null);
  final byName = {for (final g in s.groups) g.name: g};
  final top = s.groups.firstWhere((g) => g.type == 'Selector', orElse: () => s.groups.first);
  var name = top.now;
  for (var i = 0; i < 6 && byName[name] != null; i++) {
    name = byName[name]!.now;
  }
  return (name, top);
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
    return SFCard(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Tooltip(
            message: s.running ? '断开' : '连接',
            child: Tap(
              radius: 40,
              onTap: busy ? null : s.toggle,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: SF.raised,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2E2E33)),
                  boxShadow: s.running ? [BoxShadow(color: SF.accent.withValues(alpha: .08), spreadRadius: 6)] : null,
                ),
                child: PlanetMark(on: s.status == CoreStatus.running || s.status == CoreStatus.starting, lit: s.running),
              ),
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Dot(s.running ? SF.ok : (s.error != null ? SF.bad : SF.faint), halo: s.running),
                    const SizedBox(width: 8),
                    Text(switch (s.status) {
                      CoreStatus.running => '已连接',
                      CoreStatus.starting => '正在连接…',
                      CoreStatus.stopping => '正在断开…',
                      CoreStatus.stopped => s.error != null ? '连接失败' : '未连接',
                    }, style: SF.t(12.5, color: s.running ? SF.ok : (s.error != null ? SF.bad : SF.text3), weight: FontWeight.w500)),
                    if (s.startedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(fmtDuration(DateTime.now().difference(s.startedAt!)), style: SF.m(12.5, color: SF.text3)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s.running ? (node.isEmpty ? '直连' : displayName(node)) : (s.active?.name ?? '还没有配置'),
                  style: SF.t(28, weight: FontWeight.w600, height: 1.1),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (s.error != null && !s.running)
                  Text(
                    s.error!,
                    style: SF.t(12.5, color: SF.bad),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  DefaultTextStyle(
                    style: SF.t(12.5, color: SF.text3),
                    child: Row(
                      children: [
                        if (n != null && n.type.isNotEmpty) ...[Text(n.type), _sep()],
                        if (s.running) ...[
                          const Text('延迟 '),
                          Text(n?.delay == null ? '—' : (n!.delay! > 0 ? '${n.delay} ms' : '超时'), style: SF.m(12.5)),
                          _sep(),
                        ],
                        Text(s.running ? '策略组 · ${group?.name ?? '—'}' : '点击左侧按钮连接'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SFButton('切换节点', kind: BtnKind.primary, onTap: () => onGo(1)),
                const SizedBox(height: 8),
                SFButton('延迟测试', onTap: s.running && node.isNotEmpty ? () => s.testDelay([node]) : null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sep() => Container(width: 1, height: 12, color: SF.input, margin: const EdgeInsets.symmetric(horizontal: 12));
}

/// The connect control's mark. Stopped: a lone planet. Connecting: a moon
/// flies in from a fixed point, then circles once while its orbit line is
/// drawn behind it. Disconnecting: the moon leaves along the tangent at its
/// current angle and the orbit fades away.
class PlanetMark extends StatefulWidget {
  const PlanetMark({super.key, required this.on, required this.lit});

  /// [on]: the moon belongs in orbit (running or starting); [lit]: running.
  final bool on, lit;

  @override
  State<PlanetMark> createState() => _PlanetMarkState();
}

enum _Phase { idle, entering, orbiting, leaving }

/// Orbit geometry, in logical pixels around the planet's centre.
abstract final class _Orbit {
  static const rx = 27.0, ry = 9.0, tilt = -0.42;

  /// Ellipse parameter where the moon joins the orbit.
  static const entry = pi * .2;

  static Offset _rot(Offset v) => Offset(v.dx * cos(tilt) - v.dy * sin(tilt), v.dx * sin(tilt) + v.dy * cos(tilt));
  static Offset point(double a) => _rot(Offset(rx * cos(a), ry * sin(a)));
  static Offset tangent(double a) {
    final t = _rot(Offset(-rx * sin(a), ry * cos(a)));
    return t / t.distance;
  }

  /// Fixed launch point: back along the entry tangent, outside the button.
  static final Offset launch = point(entry) - tangent(entry) * 46;
}

class _PlanetMarkState extends State<PlanetMark> with SingleTickerProviderStateMixin {
  static const _fly = 650, _lap = 3200, _leave = 750; // ms

  late final Ticker _ticker = createTicker((elapsed) {
    _now = elapsed;
    if (_phase == _Phase.entering && _ms >= _fly + _lap) _phase = _Phase.orbiting;
    if (_phase == _Phase.leaving && _ms >= _leave) {
      _phase = _Phase.idle;
      _ticker.stop();
    }
    setState(() {});
  });
  Duration _now = Duration.zero, _since = Duration.zero;
  _Phase _phase = _Phase.idle;
  double _exitAngle = 0;

  int get _ms => (_now - _since).inMilliseconds;

  /// Orbit angle while entering / orbiting (keeps counting across both).
  double get _angle => _Orbit.entry + 2 * pi * max(0, _ms - _fly) / _lap;

  @override
  void initState() {
    super.initState();
    // Already connected when the page opens: no fly-in, just orbit.
    if (widget.on) {
      _begin(_Phase.orbiting);
      _since -= const Duration(milliseconds: _fly + _lap);
    }
  }

  @override
  void didUpdateWidget(PlanetMark old) {
    super.didUpdateWidget(old);
    if (widget.on && (_phase == _Phase.idle || _phase == _Phase.leaving)) {
      _begin(_Phase.entering);
    } else if (!widget.on && (_phase == _Phase.entering || _phase == _Phase.orbiting)) {
      _exitAngle = _ms < _fly ? _Orbit.entry : _angle;
      _begin(_Phase.leaving);
    }
  }

  void _begin(_Phase p) {
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _ticker.start();
    }
    _phase = p;
    _since = _now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Offset? moon;
    var moonAlpha = 0.0, arcSweep = 0.0, arcAlpha = 0.0;
    var behind = false;
    switch (_phase) {
      case _Phase.idle:
        break;
      case _Phase.entering when _ms < _fly:
        final k = Curves.easeOutCubic.transform(_ms / _fly);
        moon = Offset.lerp(_Orbit.launch, _Orbit.point(_Orbit.entry), k);
        moonAlpha = min(1, _ms / (_fly * .5));
      case _Phase.entering || _Phase.orbiting:
        final a = _angle;
        moon = _Orbit.point(a);
        moonAlpha = 1;
        behind = sin(a) < 0;
        arcSweep = min(2 * pi, a - _Orbit.entry);
        arcAlpha = 1;
      case _Phase.leaving:
        final k = (_ms / _leave).clamp(0.0, 1.0);
        moon = _Orbit.point(_exitAngle) + _Orbit.tangent(_exitAngle) * (70 * Curves.easeInCubic.transform(k) + 6 * k);
        moonAlpha = 1 - Curves.easeIn.transform(k);
        arcSweep = 2 * pi;
        arcAlpha = 1 - Curves.easeOut.transform(k);
    }
    // Own layer, so the 60 fps orbit does not repaint the hero card.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PlanetPainter(
          lit: widget.lit,
          dim: widget.on && !widget.lit,
          moon: moon,
          moonAlpha: moonAlpha,
          behind: behind,
          arcSweep: arcSweep,
          arcAlpha: arcAlpha,
        ),
      ),
    );
  }
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter({
    required this.lit,
    required this.dim,
    required this.moon,
    required this.moonAlpha,
    required this.behind,
    required this.arcSweep,
    required this.arcAlpha,
  });

  final bool lit, dim, behind;
  final Offset? moon;
  final double moonAlpha, arcSweep, arcAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 13.0;
    final planetColor = lit ? SF.accent : const Color(0xFF52525B);

    // The orbit line from the entry point, split into the half behind the
    // planet and the half in front of it.
    void orbit(bool front) {
      if (arcSweep <= 0 || arcAlpha <= 0) return;
      final path = Path();
      var open = false;
      const steps = 96;
      final n = max(2, (steps * arcSweep / (2 * pi)).ceil());
      for (var i = 0; i <= n; i++) {
        final a = _Orbit.entry + arcSweep * i / n;
        final isFront = sin(a) >= 0;
        final p = c + _Orbit.point(a);
        if (isFront == front) {
          open ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
          open = true;
        } else {
          open = false;
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = SF.accent.withValues(alpha: (front ? .35 : .18) * arcAlpha),
      );
    }

    void satellite() {
      final m = moon;
      if (m == null || moonAlpha <= 0) return;
      final p = c + m;
      final alpha = (dim ? .6 : 1.0) * moonAlpha;
      canvas.drawCircle(p, 6, Paint()..color = SF.accent.withValues(alpha: .14 * alpha));
      canvas.drawCircle(p, 3.2, Paint()..color = const Color(0xFFF6C9A8).withValues(alpha: alpha));
    }

    orbit(false);
    if (behind) satellite();

    // Planet: solid disc with a soft terminator and a thin rim light.
    if (lit) canvas.drawCircle(c, r + 5, Paint()..color = SF.accent.withValues(alpha: .10));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.45, -.5),
          radius: 1.1,
          colors: [Color.lerp(planetColor, Colors.white, .28)!, planetColor, Color.lerp(planetColor, Colors.black, .45)!],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = Colors.white.withValues(alpha: lit ? .18 : .08),
    );

    orbit(true);
    if (!behind) satellite();
  }

  @override
  bool shouldRepaint(_PlanetPainter o) => true;
}

class _Toggles extends StatelessWidget {
  const _Toggles();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    Widget row(String t, String sub, bool v, ValueChanged<bool> on, {bool last = false, bool mono = false}) => Container(
      height: 48,
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: SF.lineInner)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: SF.t(13.5, weight: FontWeight.w500)),
                Text(
                  sub,
                  style: mono ? SF.m(12, color: SF.text3) : SF.t(12, color: SF.text3),
                ),
              ],
            ),
          ),
          SFSwitch(value: v, onChanged: on),
        ],
      ),
    );
    return SFCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          row('TUN 模式', '接管全部系统流量', s.settings.tun, (v) => s.updateSettings((x) => x.tun = v)),
          row('系统代理', '127.0.0.1:${s.settings.mixedPort}', s.settings.systemProxy, s.setSystemProxy, mono: true),
          row('局域网共享', '允许其他设备连接', s.settings.allowLan, (v) => s.updateSettings((x) => x.allowLan = v), last: true),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.note, this.hist, this.color);
  final String label, note;
  final (String, String) value;
  final List<int>? hist;
  final Color color;

  @override
  Widget build(BuildContext context) => SFCard(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(label, style: SF.t(12, color: SF.text3)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                note,
                textAlign: TextAlign.right,
                style: SF.t(12, color: SF.text3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value.$1, style: SF.m(24, weight: FontWeight.w500)),
            if (value.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(value.$2, style: SF.t(12, color: SF.text3)),
              ),
            const Spacer(),
            if (hist != null)
              SizedBox(
                width: 72,
                height: 24,
                child: RepaintBoundary(child: CustomPaint(painter: _Spark(hist!, color))),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Spark extends CustomPainter {
  _Spark(this.data, this.color);
  final List<int> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Two samples of context on the left feed the moving average.
    final raw = data.sublist(data.length - 26).map((e) => e.toDouble()).toList();
    final pts = [for (var i = 2; i < raw.length; i++) (raw[i - 2] + 2 * raw[i - 1] + 3 * raw[i]) / 6];
    final mx = max(1.0, pts.reduce(max));
    final p = [for (var i = 0; i < pts.length; i++) Offset(size.width * i / (pts.length - 1), size.height - 2 - (size.height - 4) * pts[i] / mx)];
    canvas.drawPath(
      _monotone(p),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Monotone cubic (Fritsch–Carlson) through [p]: smooth, and never
  /// overshoots between samples, so a flat zero stays on the baseline.
  static Path _monotone(List<Offset> p) {
    final n = p.length;
    final d = [for (var i = 0; i < n - 1; i++) (p[i + 1].dy - p[i].dy) / (p[i + 1].dx - p[i].dx)];
    final m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : 2 / (1 / d[i - 1] + 1 / d[i]);
    }
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (var i = 0; i < n - 1; i++) {
      final h = (p[i + 1].dx - p[i].dx) / 3;
      path.cubicTo(p[i].dx + h, p[i].dy + m[i] * h, p[i + 1].dx - h, p[i + 1].dy - m[i + 1] * h, p[i + 1].dx, p[i + 1].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_Spark old) => true;
}

Color _riskColor(int? r) => r == null
    ? SF.faint
    : (r < 25
          ? SF.ok
          : r < 60
          ? SF.warn
          : SF.bad);

class _ExitIpCard extends StatelessWidget {
  const _ExitIpCard();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final ip = s.exitIp;
    Widget kv(String k, Widget v) => Container(
      height: 40,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SF.lineInner)),
      ),
      child: Row(
        children: [
          Text(k, style: SF.t(13, color: SF.text3)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: v),
          ),
        ],
      ),
    );
    return SFCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Text('出口 IP', style: SF.t(13.5, weight: FontWeight.w600)),
                const Spacer(),
                Text(
                  s.exitIpLoading ? '检测中…' : (ip != null ? '检测于 ${fmtAgo(ip.checkedAt)}' : (s.exitIpError ?? (s.running ? '' : '连接后自动检测'))),
                  style: SF.t(12, color: s.exitIpError != null ? SF.bad : SF.text3),
                ),
                const SizedBox(width: 10),
                SFIconButton(Icons.refresh_rounded, tooltip: '重新检测', size: 26, iconSize: 14, onTap: s.running && !s.exitIpLoading ? s.checkExitIp : null),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 236,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(bottom: 14),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: SF.lineInner)),
                        ),
                        child: Row(
                          children: [
                            if (ip != null && ip.countryCode.length == 2)
                              CountryFlag.fromCountryCode(ip.countryCode, theme: const ImageTheme(width: 36, height: 24, shape: RoundedRectangle(3)))
                            else
                              Container(
                                width: 36,
                                height: 24,
                                decoration: BoxDecoration(color: SF.raised, borderRadius: BorderRadius.circular(3)),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ip?.country ?? '—',
                                    style: SF.t(15, weight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(ip == null ? '未检测' : ip.countryCode, style: SF.t(12, color: SF.text3)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      kv('地理位置', Text(ip?.location ?? '—', style: SF.t(13), overflow: TextOverflow.ellipsis)),
                      kv(
                        'IP',
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(ip?.ip ?? '—', style: SF.m(13)),
                            if (ip != null)
                              SFIconButton(
                                Icons.copy_rounded,
                                tooltip: '复制 IP',
                                size: 24,
                                iconSize: 13,
                                bordered: false,
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: ip.ip));
                                  toast(context, '已复制 ${ip.ip}');
                                },
                              ),
                          ],
                        ),
                      ),
                      kv(
                        '运营商',
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: ip?.isp ?? '—', style: SF.t(13)),
                              if (ip != null)
                                TextSpan(
                                  text: '  ${ip.asn}',
                                  style: SF.m(12, color: SF.text3),
                                ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('风险度评分', style: SF.t(13, color: SF.text3)),
                          const Spacer(),
                          Text(ip?.risk == null ? '—' : '${ip!.risk}', style: SF.m(22, weight: FontWeight.w500)),
                          Text(' / 100', style: SF.m(12, color: SF.text3)),
                        ],
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (ip?.risk ?? 0) / 100,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF222226),
                          color: _riskColor(ip?.risk),
                        ),
                      ),
                      const SizedBox(height: 9),
                      if (ip != null)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(color: _riskColor(ip.risk).withValues(alpha: .12), borderRadius: BorderRadius.circular(5)),
                              child: Text(
                                ip.riskLabel,
                                style: SF.t(12, color: _riskColor(ip.risk), weight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: '数据来自 IPPure',
                                child: Text(
                                  '${ip.ipType} · ${ip.flags.join(' · ')}',
                                  style: SF.t(12, color: SF.text3),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text('数据来自 IPPure', style: SF.t(12, color: SF.text3)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0C0E),
                      border: Border.all(color: SF.lineSoft),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: WorldMap(lat: ip?.lat, lon: ip?.lon, label: ip?.location.split(' · ').last),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 12,
                          child: Text(
                            ip == null
                                ? ''
                                : '${ip.lat.abs().toStringAsFixed(2)}°${ip.lat >= 0 ? 'N' : 'S'} · ${ip.lon.abs().toStringAsFixed(2)}°${ip.lon >= 0 ? 'E' : 'W'}',
                            style: SF.m(11, color: SF.text3),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 12,
                          child: Row(
                            children: [
                              const Dot(SF.accent),
                              const SizedBox(width: 6),
                              Text('出口节点', style: SF.t(11, color: SF.text3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Outbounds extends StatelessWidget {
  const _Outbounds();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final share = s.outboundShare.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = share.fold<int>(0, (a, e) => a + e.value);
    const colors = [SF.accent, SF.text2, Color(0xFF52525B), Color(0xFF3F3F46)];
    return SFCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Text('出站分布', style: SF.t(13.5, weight: FontWeight.w600)),
                const Spacer(),
                Text('本次运行', style: SF.t(12, color: SF.text3)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (share.isEmpty)
            Expanded(
              child: Center(
                child: Text(s.running ? '还没有流量' : '未连接', style: SF.t(12.5, color: SF.text3)),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < min(share.length, 6); i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(displayName(share[i].key), style: SF.t(13), overflow: TextOverflow.ellipsis),
                              ),
                              Text(fmtBytes(share[i].value), style: SF.m(12, color: SF.text3)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: share[i].value / total,
                              minHeight: 4,
                              backgroundColor: const Color(0xFF222226),
                              color: share[i].key.toLowerCase().contains('block') || share[i].key.contains('拦截') ? SF.bad : colors[min(i, 3)],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Latency board for six well-known sites, measured through the local
/// inbound so each follows the routing rules. Click to measure again.
class _Sites extends StatelessWidget {
  const _Sites();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return SFCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: Row(
              children: [
                Text(
                  '网站测速',
                  style: SF.t(12, color: SF.text2, weight: FontWeight.w600),
                ),
                const Spacer(),
                if (s.sitesTesting)
                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.4, color: SF.text3))
                else
                  Tap(
                    radius: 4,
                    onTap: s.running ? s.testSites : null,
                    child: Icon(Icons.refresh_rounded, size: 14, color: s.running ? SF.text3 : SF.faint),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < 3; r++) ...[
            if (r > 0) const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _SiteTag(Site.all[r * 2])),
                const SizedBox(width: 6),
                Expanded(child: _SiteTag(Site.all[r * 2 + 1])),
              ],
            ),
          ],
        ],
      ),
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
      height: 20,
      padding: const EdgeInsets.only(left: 4, right: 7),
      decoration: BoxDecoration(
        color: site.color.withValues(alpha: .07),
        border: Border.all(color: site.color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.asset(site.icon, width: 12, height: 12, filterQuality: FilterQuality.medium),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              site.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SF.t(11.5, color: site.color, height: 1),
            ),
          ),
          // Fixed width so the tags stay put while numbers change.
          SizedBox(
            width: 34,
            child: AnimatedSwitcher(
              duration: SF.fast,
              child: Text(
                text,
                key: ValueKey(text),
                textAlign: TextAlign.right,
                style: SF.m(11, color: color, height: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
