import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The OS system proxy: WinINet registry on Windows, `networksetup` on macOS.
/// Toggling it never needs the core restarted, and the proxy guard can check
/// it every few seconds.
class SystemProxy {
  static const _hkcu = 0x80000001;
  static const _key = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _rtSz = 0x2, _rtDword = 0x10;

  /// Local and private ranges never go through the proxy.
  static const bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>';
  static const macBypass = ['localhost', '127.0.0.1', '::1', '*.local', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];

  /// The proxy address SingFox writes for [port].
  static String serverFor(int port) => '127.0.0.1:$port';

  /// Current `(enabled, server)`.
  static (bool, String) read() {
    if (Platform.isWindows) return _winRead();
    if (Platform.isMacOS) return _macRead();
    return (false, '');
  }

  /// Whether the system proxy is on and points at [server].
  static bool isSet(String server) {
    final (on, current) = read();
    return on && current == server;
  }

  static void set(String server) {
    if (Platform.isWindows) {
      _winWrite({'ProxyServer': server, 'ProxyOverride': bypass}, enable: 1);
    } else if (Platform.isMacOS) {
      _macSet(server);
    }
  }

  /// Turns the proxy off, but only while it is still SingFox's [server]:
  /// a proxy another app has set since is left alone.
  static void clear(String server) {
    if (Platform.isWindows) {
      if (read().$2 == server) _winWrite(const {}, enable: 0);
    } else if (Platform.isMacOS) {
      _macClear(server);
    }
  }

  // ---------------------------------------------------------------- Windows

  static (bool, String) _winRead() => using((arena) {
        final key = _key.toNativeUtf16(allocator: arena);
        final dword = arena<Uint32>(), size = arena<Uint32>();
        size.value = 4;
        final on = RegGetValue(_hkcu, key, 'ProxyEnable'.toNativeUtf16(allocator: arena), _rtDword, nullptr, dword, size) == 0 && dword.value != 0;
        final buf = arena<Uint16>(1024);
        size.value = 2048;
        final ok = RegGetValue(_hkcu, key, 'ProxyServer'.toNativeUtf16(allocator: arena), _rtSz, nullptr, buf, size) == 0;
        return (on, ok ? buf.cast<Utf16>().toDartString() : '');
      });

  static void _winWrite(Map<String, String> strings, {required int enable}) {
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
    _winNotify();
  }

  // Tell running WinINet clients the settings changed.
  static final _setOption = DynamicLibrary.open('wininet.dll')
      .lookupFunction<Int32 Function(Pointer, Uint32, Pointer, Uint32), int Function(Pointer, int, Pointer, int)>('InternetSetOptionW');

  static void _winNotify() {
    _setOption(nullptr, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
    _setOption(nullptr, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
  }

  // ---------------------------------------------------------------- macOS

  /// Active macOS network service names (excluding disabled `*` entries).
  static List<String> _macServices() {
    try {
      final r = Process.runSync('networksetup', ['-listallnetworkservices']);
      if (r.exitCode != 0) return const [];
      return parseMacServices('${r.stdout}');
    } catch (_) {
      return const [];
    }
  }

  static List<String> parseMacServices(String output) {
    final out = <String>[];
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('An asterisk') || line.startsWith('*')) continue;
      out.add(line);
    }
    return out;
  }

  static (bool, String) parseMacProxyOutput(String output) {
    var enabled = false;
    var server = '';
    var port = '';
    for (final raw in output.split('\n')) {
      final idx = raw.indexOf(':');
      if (idx < 0) continue;
      final k = raw.substring(0, idx).trim().toLowerCase();
      final v = raw.substring(idx + 1).trim();
      if (k == 'enabled') enabled = v.toLowerCase() == 'yes';
      if (k == 'server') server = v;
      if (k == 'port') port = v;
    }
    if (server.isEmpty || port.isEmpty || port == '0') return (false, '');
    return (enabled, '$server:$port');
  }

  static (bool, String) _macReadService(String service) {
    try {
      final web = parseMacProxyOutput('${Process.runSync('networksetup', ['-getwebproxy', service]).stdout}');
      if (web.$1) return web;
      final sec = parseMacProxyOutput('${Process.runSync('networksetup', ['-getsecurewebproxy', service]).stdout}');
      if (sec.$1) return sec;
      final socks = parseMacProxyOutput('${Process.runSync('networksetup', ['-getsocksfirewallproxy', service]).stdout}');
      if (socks.$1) return socks;
      return web.$2.isNotEmpty ? web : (sec.$2.isNotEmpty ? sec : socks);
    } catch (_) {
      return (false, '');
    }
  }

  static (bool, String) _macRead() {
    final svcs = _macServices();
    if (svcs.isEmpty) return (false, '');
    // Prefer any enabled service; otherwise return the first parsed server.
    (bool, String) first = (false, '');
    for (final s in svcs) {
      final cur = _macReadService(s);
      if (cur.$1) return cur;
      if (first.$2.isEmpty && cur.$2.isNotEmpty) first = cur;
    }
    return first;
  }

  static (String, String)? _splitHostPort(String server) {
    final i = server.lastIndexOf(':');
    if (i <= 0 || i >= server.length - 1) return null;
    return (server.substring(0, i), server.substring(i + 1));
  }

  static void _macSet(String server) {
    final hp = _splitHostPort(server);
    if (hp == null) return;
    final (host, port) = hp;
    for (final s in _macServices()) {
      Process.runSync('networksetup', ['-setwebproxy', s, host, port]);
      Process.runSync('networksetup', ['-setsecurewebproxy', s, host, port]);
      Process.runSync('networksetup', ['-setsocksfirewallproxy', s, host, port]);
      Process.runSync('networksetup', ['-setwebproxystate', s, 'on']);
      Process.runSync('networksetup', ['-setsecurewebproxystate', s, 'on']);
      Process.runSync('networksetup', ['-setsocksfirewallproxystate', s, 'on']);
      Process.runSync('networksetup', ['-setproxybypassdomains', s, ...macBypass]);
    }
  }

  static void _macClear(String server) {
    for (final s in _macServices()) {
      final (_, cur) = _macReadService(s);
      if (cur != server && cur.isNotEmpty) continue;
      Process.runSync('networksetup', ['-setwebproxystate', s, 'off']);
      Process.runSync('networksetup', ['-setsecurewebproxystate', s, 'off']);
      Process.runSync('networksetup', ['-setsocksfirewallproxystate', s, 'off']);
    }
  }
}
