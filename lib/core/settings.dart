import 'dart:convert';
import 'dart:math';

import 'paths.dart';

class Settings {
  int mixedPort = 7890;
  bool allowLan = false;
  bool systemProxy = false;
  /// Re-apply the system proxy when another program changes it.
  bool proxyGuard = false;
  int proxyGuardSeconds = 5;
  bool tun = false;
  String tunStack = 'auto';
  bool strictRoute = true;
  String logLevel = 'info';
  String mode = 'rule';
  String? activeProfile;
  String corePath = '';
  int apiPort = 9090;
  String apiSecret = _randomSecret();
  String delayUrl = 'https://www.gstatic.com/generate_204';
  /// Leave the handshakes out of node delay (Clash's unified-delay).
  bool unifiedDelay = false;
  /// `redirhost` (SingFox's leak-free split) or `profile` (keep the profile's `dns`).
  String dnsMode = 'redirhost';
  List<String> dnsLocal = ['https://223.5.5.5/dns-query'];
  List<String> dnsRemote = ['https://1.1.1.1/dns-query'];
  /// `off`, `task` (Task Scheduler), `registry` (Run key), or `service`.
  String autostart = 'off';
  /// Start hidden in the tray instead of showing the window.
  bool silentStart = false;
  /// Start the core as soon as SingFox launches.
  bool autoConnect = false;
  bool showTray = true;
  /// The close button hides to the tray instead of quitting.
  bool closeToTray = true;
  /// Lines kept on the log page, 100 to 1000.
  int logLines = 500;
  /// Android: let QUIC (UDP 443) through the proxy. Off rejects it so apps fall
  /// back to TCP, which proxies better than UDP; direct traffic is untouched.
  bool allowQuic = false;
  /// Android per-app routing: `all`, `bypass` (listed apps skip the VPN) or `only`.
  String appMode = 'all';
  List<String> appList = [];

  static String _randomSecret() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Map<String, dynamic> toJson() => {
        'mixedPort': mixedPort,
        'allowLan': allowLan,
        'systemProxy': systemProxy,
        'proxyGuard': proxyGuard,
        'proxyGuardSeconds': proxyGuardSeconds,
        'tun': tun,
        'tunStack': tunStack,
        'strictRoute': strictRoute,
        'logLevel': logLevel,
        'mode': mode,
        'activeProfile': activeProfile,
        'corePath': corePath,
        'apiPort': apiPort,
        'apiSecret': apiSecret,
        'delayUrl': delayUrl,
        'unifiedDelay': unifiedDelay,
        'dnsMode': dnsMode,
        'dnsLocal': dnsLocal,
        'dnsRemote': dnsRemote,
        'autostart': autostart,
        'silentStart': silentStart,
        'autoConnect': autoConnect,
        'showTray': showTray,
        'closeToTray': closeToTray,
        'logLines': logLines,
        'allowQuic': allowQuic,
        'appMode': appMode,
        'appList': appList,
      };

  static List<String>? _list(Object? v) => switch (v) {
        String s => [s],
        List l => [for (final e in l) '$e'],
        _ => null,
      };

  void _apply(Map<String, dynamic> j) {
    mixedPort = j['mixedPort'] ?? mixedPort;
    allowLan = j['allowLan'] ?? allowLan;
    systemProxy = j['systemProxy'] ?? systemProxy;
    proxyGuard = j['proxyGuard'] ?? proxyGuard;
    proxyGuardSeconds = j['proxyGuardSeconds'] ?? proxyGuardSeconds;
    tun = j['tun'] ?? tun;
    tunStack = j['tunStack'] ?? tunStack;
    strictRoute = j['strictRoute'] ?? strictRoute;
    logLevel = j['logLevel'] ?? logLevel;
    mode = j['mode'] ?? mode;
    activeProfile = j['activeProfile'];
    corePath = j['corePath'] ?? corePath;
    apiPort = j['apiPort'] ?? apiPort;
    apiSecret = j['apiSecret'] ?? apiSecret;
    delayUrl = j['delayUrl'] ?? delayUrl;
    unifiedDelay = j['unifiedDelay'] ?? unifiedDelay;
    dnsMode = j['dnsMode'] ?? dnsMode;
    dnsLocal = _list(j['dnsLocal']) ?? dnsLocal;
    dnsRemote = _list(j['dnsRemote']) ?? dnsRemote;
    autostart = j['autostart'] ?? autostart;
    silentStart = j['silentStart'] ?? silentStart;
    autoConnect = j['autoConnect'] ?? autoConnect;
    showTray = j['showTray'] ?? showTray;
    closeToTray = j['closeToTray'] ?? closeToTray;
    logLines = j['logLines'] ?? logLines;
    allowQuic = j['allowQuic'] ?? allowQuic;
    appMode = j['appMode'] ?? appMode;
    appList = _list(j['appList']) ?? appList;
  }

  static Future<Settings> load() async {
    final s = Settings();
    final f = Paths.I.settingsFile;
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        s._apply(j);
        // Keep the API secret across launches: a core started by the Quick
        // Settings tile outlives the app and was given the old one.
        if (j['apiSecret'] == null) await s.save();
      } catch (_) {}
    } else {
      await s.save();
    }
    return s;
  }

  Future<void> save() => Paths.I.settingsFile.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
}
