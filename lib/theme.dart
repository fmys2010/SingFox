import 'package:flutter/material.dart';

/// Design tokens from the SingFox desktop design (restrained dark theme).
abstract final class SF {
  static const bg = Color(0xFF09090B);
  static const surface = Color(0xFF111113);
  static const raised = Color(0xFF17171A);
  static const line = Color(0xFF1F1F23);
  static const lineSoft = Color(0xFF18181B);
  static const lineInner = Color(0xFF1C1C20);
  static const input = Color(0xFF27272A);
  static const active = Color(0xFF26262B);
  static const text = Color(0xFFEDEDEF);
  static const text2 = Color(0xFFA1A1AA);
  static const text3 = Color(0xFF8B8B94);
  static const faint = Color(0xFF52525B);
  static const accent = Color(0xFFE8834A);
  static const accentText = Color(0xFFF2A577);
  static const ok = Color(0xFF3FCF8E);
  static const warn = Color(0xFFE5B454);
  static const bad = Color(0xFFF2706B);

  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);

  static const sans = 'Segoe UI Variable Text';
  static const sansFallback = ['Segoe UI', 'Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC'];
  static const mono = 'Cascadia Mono';
  static const monoFallback = ['Consolas', 'Menlo', 'monospace', 'Microsoft YaHei UI'];

  static TextStyle t(double size, {Color color = text, FontWeight weight = FontWeight.w400, double? height}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: sansFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
      );

  static TextStyle m(double size, {Color color = text, FontWeight weight = FontWeight.w400, double? height}) => TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
      );

  static Color latency(int? ms) {
    if (ms == null || ms <= 0) return bad;
    if (ms < 80) return ok;
    if (ms < 150) return warn;
    return bad;
  }

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        fontFamily: sans,
        fontFamilyFallback: sansFallback,
        colorScheme: const ColorScheme.dark(primary: accent, surface: surface),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: const Color(0x0AFFFFFF),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: Color(0x55E8834A),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(const Color(0xFF2E2E33)),
          thickness: WidgetStateProperty.all(6),
          radius: const Radius.circular(3),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(color: raised, border: Border.all(color: input), borderRadius: BorderRadius.circular(6)),
          textStyle: t(12),
        ),
      );
}
