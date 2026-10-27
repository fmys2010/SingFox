import 'dart:convert';
import 'dart:io';

import 'dns.dart';
import 'paths.dart';
import 'profiles.dart';
import 'settings.dart';

/// Turns a profile's config into the runtime config SingFox hands the core:
/// inbounds follow the app settings, the Clash API is wired up for the UI,
/// and SingFox's own rule edits are applied.
class ConfigBuilder {
  static const mixedTag = 'singfox-mixed';
  static const tunTag = 'singfox-tun';
  static const directTag = 'direct';

  /// Rejects QUIC (UDP 443) wherever a rule sends it to a proxy, by putting a
  /// copy of that rule, narrowed to UDP 443, in front of it. What reaches
  /// `final` is covered by a catch-all at the end unless `final` is direct.
  static List<Map<String, dynamic>> _rejectProxiedQuic(List<Map<String, dynamic>> rules, String direct, String? final_) {
    const skip = {'reject', 'direct', 'block', 'dns'};
    final out = <Map<String, dynamic>>[];
    for (final r in rules) {
      final to = r['outbound'];
      final routes = to is String && to != direct && !skip.contains(to) && (r['action'] == null || r['action'] == 'route');
      final narrowable = r['type'] != 'logical' && !r.containsKey('network') && !r.containsKey('port') && !r.containsKey('port_range');
      if (routes && narrowable) {
        final twin = Map<String, dynamic>.from(r)..remove('outbound');
        out.add({...twin, 'network': 'udp', 'port': 443, 'action': 'reject'});
      }
      out.add(r);
    }
    if (final_ == null || final_ != direct) out.add({'network': 'udp', 'port': 443, 'action': 'reject'});
    return out;
  }

  static Map<String, dynamic> build(String raw, Settings s, ProfileExtras extras) {
    final cfg = jsonDecode(raw) as Map<String, dynamic>;

    cfg['log'] = {...?(cfg['log'] as Map?)?.cast<String, dynamic>(), 'level': s.logLevel, 'timestamp': true, 'disabled': false,
      // Android: the core runs inside the app; the log page follows this file.
      if (Platform.isAndroid) 'output': '${Paths.I.work.path}/box.log'};

    cfg['inbounds'] = [
      {
        'type': 'mixed',
        'tag': mixedTag,
        'listen': s.allowLan ? '::' : '127.0.0.1',
        'listen_port': s.mixedPort,
      },
      if (s.tun)
        {
          'type': 'tun',
          'tag': tunTag,
          // IPv4 only: with a v6 address the OS prefers AAAA, the TUN accepts
          // the connection locally, and a dead v6 path then stalls the app
          // instead of letting it fall back to v4.
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'strict_route': s.strictRoute,
          // Android: mixed (system stack for TCP, gVisor for UDP) is the lightest.
          if (Platform.isAndroid && s.tunStack == 'auto')
            'stack': 'mixed'
          else if (s.tunStack != 'auto')
            'stack': s.tunStack,
          if (Platform.isAndroid && s.appList.isNotEmpty && s.appMode == 'bypass') 'exclude_package': s.appList,
          if (Platform.isAndroid && s.appList.isNotEmpty && s.appMode == 'only') 'include_package': s.appList,
        },
    ];

    final outbounds = [for (final o in (cfg['outbounds'] as List? ?? [])) Map<String, dynamic>.from(o as Map)];
    var direct = outbounds.where((o) => o['type'] == 'direct').map((o) => o['tag'] as String?).firstOrNull;
    if (direct == null) {
      direct = directTag;
      outbounds.add({'type': 'direct', 'tag': directTag});
    }
    cfg['outbounds'] = outbounds;
    final globalTarget = outbounds.where((o) => o['type'] == 'selector').map((o) => o['tag'] as String?).firstOrNull ??
        outbounds.where((o) => o['type'] != 'direct' && o['type'] != 'block' && o['type'] != 'dns').map((o) => o['tag'] as String?).firstOrNull ??
        direct;

    final route = Map<String, dynamic>.from(cfg['route'] as Map? ?? {});
    final own = [for (final r in (route['rules'] as List? ?? [])) Map<String, dynamic>.from(r as Map)];
    final kept = [for (var i = 0; i < own.length; i++) if (!extras.disabledRules.contains(i)) own[i]];
    final hasHijack = own.any((r) => r['action'] == 'hijack-dns');
    final rules = <Map<String, dynamic>>[
      if (s.tun && !hasHijack) {'action': 'sniff'},
      if (s.tun && !hasHijack) {'protocol': 'dns', 'action': 'hijack-dns'},
      {'clash_mode': 'Direct', 'outbound': direct},
      {'clash_mode': 'Global', 'outbound': globalTarget},
      ...extras.rules,
      ...kept,
    ];
    route['rules'] = Platform.isAndroid && !s.allowQuic ? _rejectProxiedQuic(rules, direct, route['final'] as String?) : rules;
    final ruleSets = [for (final r in (route['rule_set'] as List? ?? [])) Map<String, dynamic>.from(r as Map)];
    final tags = {for (final r in ruleSets) r['tag']};
    for (final r in extras.ruleSets) {
      if (tags.contains(r['tag'])) continue;
      ruleSets.add({
        'tag': r['tag'],
        'type': 'remote',
        'format': 'binary',
        'url': r['url'],
        if (r['detour'] != null) 'http_client': {'detour': r['detour']},
      });
    }
    if (ruleSets.isNotEmpty) route['rule_set'] = ruleSets;
    if (s.tun) route['auto_detect_interface'] = true;
    cfg['route'] = route;
    if (s.dnsMode == 'redirhost') DnsPlan.apply(cfg, s, globalTarget);
    if (s.tun) {
      // Answer AAAA with an empty NOERROR so apps use IPv4 straight away.
      final dns = Map<String, dynamic>.from(cfg['dns'] as Map? ?? {});
      dns['rules'] = [
        {'query_type': ['AAAA'], 'action': 'predefined', 'rcode': 'NOERROR'},
        ...?(dns['rules'] as List?),
      ];
      cfg['dns'] = dns;
    }

    final exp = Map<String, dynamic>.from(cfg['experimental'] as Map? ?? {});
    exp['clash_api'] = {
      'external_controller': '127.0.0.1:${s.apiPort}',
      'secret': s.apiSecret,
      'default_mode': switch (s.mode) { 'global' => 'Global', 'direct' => 'Direct', _ => 'Rule' },
    };
    exp['cache_file'] = {
      ...?(exp['cache_file'] as Map?)?.cast<String, dynamic>(),
      'enabled': true,
      'path': '${Paths.I.work.path}/cache.db',
    };
    cfg['experimental'] = exp;
    return cfg;
  }
}
