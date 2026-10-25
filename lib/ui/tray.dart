import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import 'widgets.dart';

/// Whether the window is on screen (not minimised or hidden in the tray).
/// The UI skips rebuilds and pauses animations while it is false.
final appVisible = ValueNotifier(true);

/// The notification-area icon: click to show the window, right-click for
/// connect, mode, system proxy, TUN and quit. Follows `Settings.showTray`.
class SFTray with TrayListener {
  SFTray._();
  static final I = SFTray._();

  bool _shown = false;
  String _menuKey = '';
  final s = AppState.I;

  /// Makes Windows draw the tray's popup menu dark, to match the app. These
  /// are uxtheme's unnamed exports 135 (SetPreferredAppMode) and 136
  /// (FlushMenuThemes); a Windows without them just keeps the light menu.
  static void _darkMenus() {
    try {
      final k = DynamicLibrary.open('kernel32.dll');
      final load = k.lookupFunction<IntPtr Function(Pointer<Uint16>), int Function(Pointer<Uint16>)>('LoadLibraryW');
      final proc = k.lookupFunction<Pointer Function(IntPtr, IntPtr), Pointer Function(int, int)>('GetProcAddress');
      final name = [...'uxtheme.dll'.codeUnits, 0];
      final buf = calloc<Uint16>(name.length)..asTypedList(name.length).setAll(0, name);
      final ux = load(buf);
      calloc.free(buf);
      final setMode = proc(ux, 135);
      final flush = proc(ux, 136);
      if (setMode != nullptr) setMode.cast<NativeFunction<Int32 Function(Int32)>>().asFunction<int Function(int)>()(2); // ForceDark
      if (flush != nullptr) flush.cast<NativeFunction<Void Function()>>().asFunction<void Function()>()();
    } catch (_) {}
  }

  Future<void> init() async {
    if (!Platform.isWindows) return;
    _darkMenus();
    trayManager.addListener(this);
    s.addListener(_sync);
    await _sync();
  }

  Future<void> _sync() async {
    final want = s.settings.showTray;
    if (want != _shown) {
      _shown = want;
      if (!want) {
        _menuKey = '';
        return trayManager.destroy();
      }
      await trayManager.setIcon('assets/tray/tray.ico');
    }
    if (!want) return;
    final st = s.settings;
    final node = s.groups.firstOrNull?.now ?? '';
    final key = '${s.status}|${st.mode}|${st.systemProxy}|${st.tun}|$node';
    if (key == _menuKey) return;
    _menuKey = key;
    final state = switch (s.status) {
      CoreStatus.running => '已连接${node.isEmpty ? '' : ' · ${displayName(node)}'}',
      CoreStatus.starting => '正在连接…',
      CoreStatus.stopping => '正在断开…',
      CoreStatus.stopped => '未连接',
    };
    await trayManager.setToolTip('SingFox · $state');
    MenuItem mode(String v, String label) => MenuItem.checkbox(label: label, checked: st.mode == v, onClick: (_) => s.setMode(v));
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(label: '显示 SingFox', onClick: (_) => show()),
      MenuItem.separator(),
      MenuItem(label: state, disabled: true),
      MenuItem(label: s.running ? '断开' : '连接', disabled: s.status == CoreStatus.starting || s.status == CoreStatus.stopping, onClick: (_) => s.toggle()),
      MenuItem.separator(),
      mode('rule', '规则模式'),
      mode('global', '全局模式'),
      mode('direct', '直连模式'),
      MenuItem.separator(),
      MenuItem.checkbox(label: '系统代理', checked: st.systemProxy, onClick: (_) => s.setSystemProxy(!st.systemProxy)),
      MenuItem.checkbox(label: 'TUN 模式', checked: st.tun, onClick: (_) => s.updateSettings((x) => x.tun = !x.tun)),
      MenuItem.separator(),
      MenuItem(label: '退出', onClick: (_) => quit()),
    ]));
  }

  static Future<void> show() async {
    appVisible.value = true;
    await windowManager.show();
    await windowManager.focus();
  }

  static bool _quitting = false;

  /// Stops the core and exits, whatever `closeToTray` says.
  ///
  /// Called from a tray menu click, which arrives while Windows still runs
  /// the popup menu's modal loop; tearing the window down from inside it
  /// hung the app. So it first yields, bounds the core shutdown, removes
  /// the icon (or it lingers until hovered) and then ends the process.
  static Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await windowManager.hide();
    try {
      await AppState.I.shutdown().timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      if (I._shown) await trayManager.destroy().timeout(const Duration(seconds: 1));
    } catch (_) {}
    exit(0);
  }

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() {
    // Without taking the foreground first, the popup menu never closes when
    // you click elsewhere.
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }
}
