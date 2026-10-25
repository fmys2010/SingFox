import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/widgets.dart';

/// Phone-sized building blocks; they share SF's colors with the desktop UI.
class MCard extends StatelessWidget {
  const MCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 14, this.color, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color, borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? SF.surface,
          border: Border.all(color: borderColor ?? SF.line),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
}

class MSwitch extends StatelessWidget {
  const MSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 52,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: SF.medium,
                curve: Curves.easeOutCubic,
                width: 44,
                height: 26,
                padding: const EdgeInsets.all(3),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(color: value ? SF.accent : SF.input, borderRadius: BorderRadius.circular(13)),
                child: Container(width: 20, height: 20, decoration: BoxDecoration(color: value ? Colors.white : SF.text3, shape: BoxShape.circle)),
              ),
            ),
          ),
        ),
      );
}

/// A row inside a card: title, optional subtitle, a trailing widget.
class MRow extends StatelessWidget {
  const MRow(this.title, {super.key, this.sub, this.trailing, this.onTap, this.last = false, this.mono = false});
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last, mono;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: SF.lineInner))),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: SF.t(14.5, weight: FontWeight.w500)),
                  if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: mono ? SF.m(12, color: SF.text3) : SF.t(12, color: SF.text3))),
                ]),
              ),
            ),
            ?trailing,
          ]),
        ),
      );
}

/// Full-width pill switcher (规则 / 全局 / 直连).
class MSegmented<T> extends StatelessWidget {
  const MSegmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: SF.surface, border: Border.all(color: SF.line), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: SF.fast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: v == value ? SF.active : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                  child: Text(label, style: SF.t(13, color: v == value ? SF.text : SF.text3, weight: FontWeight.w500)),
                ),
              ),
            ),
        ]),
      );
}

enum MBtn { primary, secondary, danger }

class MButton extends StatelessWidget {
  const MButton(this.label, {super.key, this.onTap, this.kind = MBtn.secondary, this.height = 44, this.icon});
  final String label;
  final VoidCallback? onTap;
  final MBtn kind;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final (bg, fg, border) = switch (kind) {
      MBtn.primary => (on ? SF.text : SF.active, on ? SF.bg : SF.text3, Colors.transparent),
      MBtn.secondary => (Colors.transparent, on ? SF.text : SF.text3, SF.input),
      MBtn.danger => (Colors.transparent, on ? SF.bad : SF.text3, SF.input),
    };
    return Tap(
      onTap: onTap,
      radius: 10,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
          Text(label, style: SF.t(14, color: fg, weight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class MIconButton extends StatelessWidget {
  const MIconButton(this.icon, {super.key, required this.label, this.onTap, this.color = SF.text2});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tap(
          onTap: onTap,
          radius: 10,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: onTap == null ? SF.faint : color),
          ),
        ),
      );
}

class MSearch extends StatelessWidget {
  const MSearch({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: SF.surface, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.search_rounded, size: 18, color: SF.text3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              cursorColor: SF.accent,
              style: SF.t(14),
              decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: SF.t(14, color: SF.text3)),
            ),
          ),
        ]),
      );
}

/// A smooth line over the last samples, like the desktop sparkline.
class Spark extends StatelessWidget {
  const Spark(this.data, this.color, {super.key, this.width = 56, this.height = 22});
  final List<int> data;
  final Color color;
  final double width, height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: RepaintBoundary(child: CustomPaint(painter: _SparkPainter(data, color))),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data, this.color);
  final List<int> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = data.sublist(max(0, data.length - 26)).map((e) => e.toDouble()).toList();
    if (raw.length < 4) return;
    final pts = [for (var i = 2; i < raw.length; i++) (raw[i - 2] + 2 * raw[i - 1] + 3 * raw[i]) / 6];
    final mx = max(1.0, pts.reduce(max));
    final p = [for (var i = 0; i < pts.length; i++) Offset(size.width * i / (pts.length - 1), size.height - 2 - (size.height - 4) * pts[i] / mx)];
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (var i = 1; i < p.length; i++) {
      final mid = Offset((p[i - 1].dx + p[i].dx) / 2, (p[i - 1].dy + p[i].dy) / 2);
      path.quadraticBezierTo(p[i - 1].dx, p[i - 1].dy, mid.dx, mid.dy);
    }
    path.lineTo(p.last.dx, p.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

void mtoast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      backgroundColor: SF.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: SF.input)),
      content: Row(children: [
        Dot(error ? SF.bad : SF.ok),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: SF.t(13))),
      ]),
    ));
}

/// Page title row shared by the tab pages.
class MHeader extends StatelessWidget {
  const MHeader(this.title, {super.key, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: Row(children: [
          Text(title, style: SF.t(22, weight: FontWeight.w600)),
          const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
        ]),
      );
}
