import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The WinINet (system) proxy, read and written in-process through the
/// registry so toggling it never needs the core restarted, and the proxy
/// guard can check it cheaply every few seconds.
class SystemProxy {
  static const _hkcu = 0x80000001;
  static const _key = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _rtSz = 0x2, _rtDword = 0x10;

  /// Local and private ranges never go through the proxy.
  static const bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';

  /// The proxy address SingFox writes for [port].
  static String serverFor(int port) => '127.0.0.1:$port';

  /// Current `(enabled, server)`.
  static (bool, String) read() {
    if (!Platform.isWindows) return (false, '');
    return using((arena) {
      final key = _key.toNativeUtf16(allocator: arena);
      final dword = arena<Uint32>(), size = arena<Uint32>();
      size.value = 4;
      final on = RegGetValue(_hkcu, key, 'ProxyEnable'.toNativeUtf16(allocator: arena), _rtDword, nullptr, dword, size) == 0 && dword.value != 0;
      final buf = arena<Uint16>(1024);
      size.value = 2048;
      final ok = RegGetValue(_hkcu, key, 'ProxyServer'.toNativeUtf16(allocator: arena), _rtSz, nullptr, buf, size) == 0;
      return (on, ok ? buf.cast<Utf16>().toDartString() : '');
    });
  }

  /// Whether the system proxy is on and points at [server].
  static bool isSet(String server) {
    final (on, current) = read();
    return on && current == server;
  }

  static void set(String server) {
    _write({'ProxyServer': server, 'ProxyOverride': bypass}, enable: 1);
  }

  /// Turns the proxy off, but only while it is still SingFox's [server]:
  /// a proxy another app has set since is left alone.
  static void clear(String server) {
    if (read().$2 == server) _write(const {}, enable: 0);
  }

  static void _write(Map<String, String> strings, {required int enable}) {
    if (!Platform.isWindows) return;
    using((arena) {
      final h = arena<IntPtr>();
      if (RegOpenKeyEx(_hkcu, _key.toNativeUtf16(allocator: arena), 0, KEY_SET_VALUE, h) != 0) return;
      try {
        for (final MapEntry(:key, :value) in strings.entries) {
          final data = value.toNativeUtf16(allocator: arena);
          RegSetValueEx(h.value, key.toNativeUtf16(allocator: arena), 0, REG_SZ, data.cast(), (value.length + 1) * 2);
        }
        final d = arena<Uint32>()..value = enable;
        RegSetValueEx(h.value, 'ProxyEnable'.toNativeUtf16(allocator: arena), 0, REG_DWORD, d.cast(), 4);
      } finally {
        RegCloseKey(h.value);
      }
    });
    _notify();
  }

  // Tell running WinINet clients the settings changed.
  static final _setOption = DynamicLibrary.open('wininet.dll')
      .lookupFunction<Int32 Function(Pointer, Uint32, Pointer, Uint32), int Function(Pointer, int, Pointer, int)>('InternetSetOptionW');

  static void _notify() {
    _setOption(nullptr, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
    _setOption(nullptr, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
  }
}
