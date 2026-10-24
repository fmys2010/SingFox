import 'dart:io';

import 'settings.dart';

/// Leak-free redir-host DNS split that SingFox writes over a profile's `dns`
/// section. Clients always get real addresses, and no domain outside the
/// mainland list ever reaches a local resolver:
///
/// 1. Mainland and private domains go to the local servers; known foreign
///    domains go to the remote servers, which are dialed through the proxy.
/// 2. Any other domain is first asked of the remote servers (`evaluate`).
///    Only if the answer lies in China is it asked again locally, so the
///    connection gets the nearest CDN node; otherwise the remote answer is
///    returned as is (`respond`).
///
/// With several servers in a group, they are queried in parallel and the
/// first successful answer wins (`race`). `reverse_mapping` lets the router
/// map a TUN connection's address back to the domain it was resolved from.
class DnsPlan {
  static const maxServers = 4;
  static const bootstrap = 'sf-bootstrap';

  static const cnSites = 'sf-geosite-cn';
  static const privateSites = 'sf-geosite-private';
  static const foreignSites = 'sf-geosite-geolocation-!cn';
  static const cnIps = 'sf-geoip-cn';

  static const _base = 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo';
  static const ruleSetUrls = {
    cnSites: '$_base/geosite/cn.srs',
    privateSites: '$_base/geosite/private.srs',
    foreignSites: '$_base/geosite/geolocation-!cn.srs',
    cnIps: '$_base/geoip/cn.srs',
  };

  static String localTag(int i) => 'sf-local-${i + 1}';
  static String remoteTag(int i) => 'sf-remote-${i + 1}';

  /// Applies the plan to [cfg] in place. [proxy] is the outbound the remote
  /// servers and the rule-set downloads go through.
  static void apply(Map<String, dynamic> cfg, Settings s, String proxy) {
    final dns = Map<String, dynamic>.from(cfg['dns'] as Map? ?? {});
    final servers = [
      for (final e in (dns['servers'] as List? ?? []))
        if (!'${(e as Map)['tag']}'.startsWith('sf-') && e['type'] != 'fakeip') Map<String, dynamic>.from(e),
    ];
    final localSpecs = _clamp(s.dnsLocal);
    final remoteSpecs = _clamp(s.dnsRemote);
    final locals = [for (var i = 0; i < localSpecs.length; i++) localTag(i)];
    final remotes = [for (var i = 0; i < remoteSpecs.length; i++) remoteTag(i)];
    var needsBootstrap = false;
    for (var i = 0; i < localSpecs.length; i++) {
      final e = server(localSpecs[i], locals[i]);
      if (_isName(e)) {
        e['domain_resolver'] = bootstrap;
        needsBootstrap = true;
      }
      servers.add(e);
    }
    for (var i = 0; i < remoteSpecs.length; i++) {
      final e = server(remoteSpecs[i], remotes[i])..['detour'] = proxy;
      if (_isName(e)) e['domain_resolver'] = locals.first;
      servers.add(e);
    }
    if (needsBootstrap) servers.add({'type': 'local', 'tag': bootstrap});

    dns
      ..remove('fakeip')
      ..['servers'] = servers
      ..['rules'] = [
        ..._group({'clash_mode': 'Direct'}, locals, 'direct'),
        ..._group({'clash_mode': 'Global'}, remotes, 'global'),
        ..._group({'rule_set': [privateSites, cnSites]}, locals, 'cn'),
        ..._group({'rule_set': foreignSites}, remotes, 'foreign'),
        // Unknown domains: ask the remote side only, then re-ask locally
        // when the answer is a mainland address.
        for (var i = 0; i < remotes.length; i++) {'action': 'evaluate', 'server': remotes[i], if (remotes.length > 1) 'tag': 'probe-$i'},
        if (remotes.length == 1) ...[
          {'match_response': true, 'rule_set': cnIps, 'server': locals.first},
          {'action': 'respond'},
        ] else ...[
          for (var i = 0; i < remotes.length; i++)
            {'match_response': 'probe-$i', 'rule_set': cnIps, 'action': 'route', 'server': locals.first, 'race': true},
          for (var i = 0; i < remotes.length; i++)
            {'match_response': 'probe-$i', 'response_rcode': 'NOERROR', 'action': 'respond', 'race': true},
          {'match_response': 'probe-0', 'action': 'respond'},
        ],
      ]
      ..['final'] = remotes.first
      ..['reverse_mapping'] = true
      ..['optimistic'] = true;
    cfg['dns'] = dns;

    final route = Map<String, dynamic>.from(cfg['route'] as Map? ?? {});
    // Proxy server names and direct dials resolve locally; routing those
    // through the rules would send the proxy's own name through the proxy.
    route['default_domain_resolver'] = locals.first;
    final ruleSets = [for (final r in (route['rule_set'] as List? ?? [])) Map<String, dynamic>.from(r as Map)];
    final have = {for (final r in ruleSets) r['tag']};
    for (final MapEntry(key: tag, value: url) in ruleSetUrls.entries) {
      if (have.contains(tag)) continue;
      ruleSets.add({'tag': tag, 'type': 'remote', 'format': 'binary', 'url': url, 'http_client': {'detour': proxy}});
    }
    route['rule_set'] = ruleSets;
    cfg['route'] = route;

    // Outbounds pointing at resolvers the plan dropped fall back to local.
    final tags = {for (final e in servers) e['tag']};
    for (final o in (cfg['outbounds'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final r = o['domain_resolver'];
      final tag = r is Map ? r['server'] : r;
      if (tag != null && !tags.contains(tag)) o['domain_resolver'] = locals.first;
    }
  }

  /// Rules sending queries matching [when] to [servers]: a plain route for
  /// one server, otherwise a parallel query where the first successful
  /// answer wins and the first server's answer is the fallback.
  static List<Map<String, dynamic>> _group(Map<String, dynamic> when, List<String> servers, String name) {
    if (servers.length == 1) return [{...when, 'server': servers.first}];
    return [
      for (var i = 0; i < servers.length; i++) {...when, 'action': 'evaluate', 'server': servers[i], 'tag': '$name-$i'},
      for (var i = 0; i < servers.length; i++) {'match_response': '$name-$i', 'response_rcode': 'NOERROR', 'action': 'respond', 'race': true},
      {'match_response': '$name-0', 'action': 'respond'},
    ];
  }

  static List<String> _clamp(List<String> specs) {
    final l = [for (final e in specs) if (e.trim().isNotEmpty) e.trim()];
    return l.isEmpty ? const ['local'] : l.take(maxServers).toList();
  }

  /// Parses a resolver written as `https://1.1.1.1/dns-query`, `tls://dns.google`,
  /// `quic://…`, `h3://…`, `tcp://…`, `udp://…`, a bare address, or `local`.
  static Map<String, dynamic> server(String spec, String tag) {
    final t = spec.trim();
    if (t.isEmpty || t == 'local' || t == 'system') return {'type': 'local', 'tag': tag};
    if (t == 'dhcp') return {'type': 'dhcp', 'tag': tag};
    final uri = Uri.tryParse(t.contains('://') ? t : 'udp://$t');
    if (uri == null || uri.host.isEmpty) return {'type': 'udp', 'tag': tag, 'server': t};
    final type = switch (uri.scheme) { 'https' => 'https', 'h3' => 'h3', 'quic' => 'quic', 'tls' => 'tls', 'tcp' => 'tcp', _ => 'udp' };
    return {
      'type': type,
      'tag': tag,
      'server': uri.host,
      if (uri.hasPort) 'server_port': uri.port,
      if ((type == 'https' || type == 'h3') && uri.path.isNotEmpty && uri.path != '/dns-query') 'path': uri.path,
    };
  }

  static bool _isName(Map<String, dynamic> server) {
    final host = server['server'] as String?;
    return host != null && InternetAddress.tryParse(host) == null;
  }
}
