import 'dart:convert';

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

  static Map<String, dynamic> build(String raw, Settings s, ProfileExtras extras) {
    final cfg = jsonDecode(raw) as Map<String, dynamic>;

    cfg['log'] = {...?(cfg['log'] as Map?)?.cast<String, dynamic>(), 'level': s.logLevel, 'timestamp': true, 'disabled': false};

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
          if (s.tunStack != 'auto') 'stack': s.tunStack,
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
    route['rules'] = [
      if (s.tun && !hasHijack) {'action': 'sniff'},
      if (s.tun && !hasHijack) {'protocol': 'dns', 'action': 'hijack-dns'},
      {'clash_mode': 'Direct', 'outbound': direct},
      {'clash_mode': 'Global', 'outbound': globalTarget},
      ...extras.rules,
      ...kept,
    ];
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
