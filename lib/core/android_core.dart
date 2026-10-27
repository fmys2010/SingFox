import 'dart:async';

import 'package:flutter/services.dart';

/// The sing-box core on Android runs inside a VpnService (libbox); this is the
/// bridge to it. The Clash API stays the way the UI talks to the core.
class AndroidCore {
  AndroidCore._();
  static final I = AndroidCore._();

  static const _method = MethodChannel('top.singfox/core');
  static const _events = EventChannel('top.singfox/core_state');

  /// Emits `{running: bool, error: String?}` whenever the VPN goes up or down.
  Stream<Map<String, dynamic>> get states => _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));

  /// Asks for the VPN permission if needed, then starts the core with [config].
  /// Throws a [PlatformException] with a readable message on failure.
  Future<void> start(String config) => _method.invokeMethod('start', {'config': config});

  Future<void> stop() => _method.invokeMethod('stop');

  Future<String> version() async => await _method.invokeMethod<String>('version') ?? '';

  /// Installed apps with a launcher entry, sorted by name.
  Future<List<({String package, String label})>> apps() async {
    final l = await _method.invokeMethod<List>('apps') ?? [];
    return [for (final m in l) (package: '${(m as Map)['package']}', label: '${m['label']}')];
  }

  Future<Uint8List?> appIcon(String package) => _method.invokeMethod<Uint8List>('appIcon', {'package': package});

  Future<bool> isRunning() async => await _method.invokeMethod<bool>('isRunning') ?? false;
}
