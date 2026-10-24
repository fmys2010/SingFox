import 'package:flutter/material.dart';

import '../theme.dart';

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${u[i]}';
}

/// Splits a rate into value and unit for the big numbers on the overview.
(String, String) fmtRate(num b) {
  final s = fmtBytes(b).split(' ');
  return (s[0], '${s[1]}/s');
}

/// Splits a leading flag emoji ("🇺🇸LAX") into its country code and the rest.
/// Windows has no flag glyphs, so names are shown without it.
(String?, String) splitFlag(String name) {
  final r = name.runes.toList();
  bool ri(int c) => c >= 0x1F1E6 && c <= 0x1F1FF;
  if (r.length >= 2 && ri(r[0]) && ri(r[1])) {
    final rest = String.fromCharCodes(r.skip(2)).trim();
    return (String.fromCharCodes([r[0] - 0x1F1E6 + 65, r[1] - 0x1F1E6 + 65]), rest.isEmpty ? name : rest);
  }
  return (null, name);
}

String displayName(String name) => splitFlag(name).$2;

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

String fmtAgo(DateTime? t) {
  if (t == null) return '从未';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 5) return '刚刚';
  if (d.inSeconds < 60) return '${d.inSeconds} 秒前';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}

class SFCard extends StatelessWidget {
  const SFCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color, this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color, borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? SF.surface,
          border: Border.all(color: borderColor ?? SF.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 6, this.halo = false});
  final Color color;
  final double size;
  final bool halo;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: halo ? [BoxShadow(color: color.withValues(alpha: .18), spreadRadius: 3)] : null,
        ),
      );
}

class OutlineTag extends StatelessWidget {
  const OutlineTag(this.text, {super.key, this.mono = true, this.color = SF.text2});
  final String text;
  final bool mono;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: mono ? SF.m(11.5, color: color) : SF.t(11.5, color: color)),
      );
}

enum BtnKind { primary, secondary, ghost, danger }

class SFButton extends StatelessWidget {
  const SFButton(this.label, {super.key, this.onTap, this.icon, this.kind = BtnKind.secondary, this.height = 34, this.trailing});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final BtnKind kind;
  final double height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (enabled ? SF.text : SF.active, enabled ? SF.bg : SF.text3, Colors.transparent),
      BtnKind.secondary => (Colors.transparent, enabled ? SF.text : SF.text3, SF.input),
      BtnKind.ghost => (Colors.transparent, enabled ? SF.text2 : SF.faint, Colors.transparent),
      BtnKind.danger => (Colors.transparent, SF.bad, SF.input),
    };
    return _Hover(
      onTap: onTap,
      radius: 8,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
          Text(label, style: SF.t(13, color: fg, weight: FontWeight.w500)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

class SFIconButton extends StatelessWidget {
  const SFIconButton(this.icon, {super.key, required this.tooltip, this.onTap, this.size = 34, this.bordered = true, this.color = SF.text2, this.iconSize = 15});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size, iconSize;
  final bool bordered;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: _Hover(
          onTap: onTap,
          radius: 8,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: bordered ? Border.all(color: SF.input) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: iconSize, color: onTap == null ? SF.faint : color),
          ),
        ),
      );
}

/// Pointer cursor plus a faint hover wash for custom buttons.
class _Hover extends StatefulWidget {
  const _Hover({required this.child, this.onTap, this.radius = 8});
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = _down = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapUp: on ? (_) => setState(() => _down = false) : null,
        onTapCancel: on ? () => setState(() => _down = false) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: SF.fast,
          curve: Curves.easeOut,
          // passthrough: the wash must cover exactly the child's own size.
          child: Stack(fit: StackFit.passthrough, children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _h && on ? 1 : 0,
                  duration: SF.fast,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(widget.radius)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class Tap extends StatelessWidget {
  const Tap({super.key, required this.child, this.onTap, this.radius = 8});
  final Widget child;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => _Hover(onTap: onTap, radius: radius, child: child);
}

class SFSwitch extends StatelessWidget {
  const SFSwitch({super.key, required this.value, this.onChanged, this.small = false});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final w = small ? 30.0 : 34.0, h = small ? 18.0 : 20.0, k = h - 4;
    return Semantics(
      toggled: value,
      child: MouseRegion(
        cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: SF.medium,
            curve: Curves.easeOutCubic,
            width: w,
            height: h,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? SF.accent : SF.input,
              borderRadius: BorderRadius.circular(h / 2),
            ),
            child: AnimatedContainer(
              duration: SF.medium,
              width: k,
              height: k,
              decoration: BoxDecoration(color: value ? Colors.white : SF.text3, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

double _textWidth(String s, TextStyle style) =>
    (TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)..layout()).width;

/// Pill switcher; the highlight slides to the chosen option.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.mono = false, this.dense = false, this.background = SF.surface});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool mono, dense;
  final Color background;

  static const _pad = 13.0, _gap = 2.0;

  TextStyle _style(bool on) => mono ? SF.m(12, color: on ? SF.text : SF.text3) : SF.t(12.5, color: on ? SF.text : SF.text3, weight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final h = dense ? 26.0 : 28.0;
    final widths = [for (final (_, label) in options) (_textWidth(label, _style(true)) + 2 * _pad).ceilToDouble()];
    final sel = options.indexWhere((o) => o.$1 == value);
    var left = 0.0;
    for (var i = 0; i < sel; i++) {
      left += widths[i] + _gap;
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: background, border: Border.all(color: SF.line), borderRadius: BorderRadius.circular(9)),
      child: Stack(children: [
        if (sel >= 0)
          AnimatedPositioned(
            duration: SF.medium,
            curve: Curves.easeOutCubic,
            left: left,
            top: 0,
            width: widths[sel],
            height: h,
            child: DecoratedBox(decoration: BoxDecoration(color: SF.active, borderRadius: BorderRadius.circular(6))),
          ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == options.length - 1 ? 0 : _gap),
              child: Tap(
                radius: 6,
                onTap: () => onChanged(options[i].$1),
                child: SizedBox(
                  width: widths[i],
                  height: h,
                  child: Center(
                    child: AnimatedDefaultTextStyle(duration: SF.fast, style: _style(i == sel), child: Text(options[i].$2, maxLines: 1, softWrap: false)),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Text tabs over a hairline; the underline slides to the chosen tab.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.items, required this.index, required this.onChanged, this.trailing});

  /// (label, count or null)
  final List<(String, String?)> items;
  final int index;
  final ValueChanged<int> onChanged;
  final Widget? trailing;

  static const _gap = 22.0;

  @override
  Widget build(BuildContext context) {
    final label = SF.t(13, weight: FontWeight.w500), count = SF.m(11.5);
    final widths = [
      for (final (l, c) in items) (_textWidth(l, label) + (c == null ? 0 : 6 + _textWidth(c, count))).ceilToDouble(),
    ];
    var left = 0.0;
    for (var i = 0; i < index && i < items.length; i++) {
      left += widths[i] + _gap;
    }
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SF.line))),
      child: Stack(children: [
        Row(children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: Tap(
                onTap: () => onChanged(i),
                radius: 0,
                child: SizedBox(
                  height: 36,
                  width: widths[i],
                  child: Row(children: [
                    AnimatedDefaultTextStyle(duration: SF.fast, style: label.copyWith(color: i == index ? SF.text : SF.text3), child: Text(items[i].$1, maxLines: 1, softWrap: false)),
                    if (items[i].$2 != null) ...[const SizedBox(width: 6), Text(items[i].$2!, style: count.copyWith(color: SF.text3))],
                  ]),
                ),
              ),
            ),
          const Spacer(),
          ?trailing,
        ]),
        if (index >= 0 && index < items.length)
          AnimatedPositioned(
            duration: SF.medium,
            curve: Curves.easeOutCubic,
            left: left,
            bottom: 0,
            width: widths[index],
            height: 1.5,
            child: const ColoredBox(color: SF.text),
          ),
      ]),
    );
  }
}

class SFInput extends StatelessWidget {
  const SFInput({super.key, this.controller, this.hint, this.icon, this.width, this.mono = false, this.onChanged, this.height = 34, this.background = SF.surface, this.textAlign = TextAlign.start, this.onSubmitted});

  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final double? width;
  final bool mono;
  final ValueChanged<String>? onChanged, onSubmitted;
  final double height;
  final Color background;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(color: background, border: Border.all(color: SF.input), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 15, color: SF.text3), const SizedBox(width: 8)],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textAlign: textAlign,
              cursorColor: SF.accent,
              cursorWidth: 1.5,
              style: mono ? SF.m(12.5) : SF.t(13),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: mono ? SF.m(12.5, color: SF.text3) : SF.t(13, color: SF.text3),
              ),
            ),
          ),
        ]),
      );
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const []});
  final String title;
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: Row(children: [
          Text(title, style: SF.t(20, weight: FontWeight.w600)),
          if (subtitle != null) ...[const SizedBox(width: 12), DefaultTextStyle(style: SF.t(12.5, color: SF.text3), child: subtitle!)],
          const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
        ]),
      );
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.icon = Icons.power_settings_new_rounded, this.action});
  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: SF.faint),
          const SizedBox(height: 12),
          Text(text, style: SF.t(13, color: SF.text3)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

/// Shows a short message at the bottom of the window.
void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 420,
      backgroundColor: SF.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: SF.input)),
      content: Row(children: [
        Dot(error ? SF.bad : SF.ok),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: SF.t(13))),
      ]),
    ));
}

/// Cross-fades between children with a short upward slide; give each child
/// a distinct key.
class FadeSlideSwitcher extends StatelessWidget {
  const FadeSlideSwitcher({super.key, required this.child, this.offset = 8});
  final Widget child;
  final double offset;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: SF.medium,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, alignment: Alignment.topLeft, children: [...previous, ?current]),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: AnimatedBuilder(
            animation: anim,
            builder: (context, c) => Transform.translate(offset: Offset(0, offset * (1 - anim.value)), child: c),
            child: child,
          ),
        ),
        child: child,
      );
}

/// Square check box; the tick scales in when checked.
class SFCheck extends StatelessWidget {
  const SFCheck(this.on, {super.key});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: SF.fast,
        curve: Curves.easeOut,
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? SF.accent : SF.accent.withValues(alpha: 0),
          border: Border.all(color: on ? SF.accent : const Color(0xFF3A3A40)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: AnimatedScale(
          scale: on ? 1 : 0,
          duration: SF.fast,
          curve: Curves.easeOutBack,
          child: const Icon(Icons.check_rounded, size: 13, color: SF.bg),
        ),
      );
}
