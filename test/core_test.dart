import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singfox/core/config_builder.dart';
import 'package:singfox/core/dns.dart';
import 'package:singfox/core/paths.dart';
import 'package:singfox/core/profiles.dart';
import 'package:singfox/core/rule_market.dart';
import 'package:singfox/core/settings.dart';
import 'package:singfox/core/sysproxy.dart';
import 'package:singfox/core/updater.dart';
import 'package:singfox/editor/schema.dart';

const _profile = '''{
  "log": { "level": "warn" },
  "inbounds": [{ "type": "mixed", "tag": "in", "listen_port": 1080 }],
  "outbounds": [
    { "type": "vless", "tag": "hk", "server": "203.0.113.8", "server_port": 443, "uuid": "bf000d23-0752-40b4-affe-68f7707a9661",
      "tls": { "enabled": true, "server_name": "example.com" },
      "transport": { "type": "xhttp", "path": "/x" } },
    { "type": "selector", "tag": "节点选择", "outbounds": ["hk"] }
  ],
  "route": {
    "rules": [{ "ip_is_private": true, "outbound": "节点选择" }, { "domain_suffix": ["cn"], "outbound": "节点选择" }],
    "final": "节点选择"
  }
}''';

void main() {
  final core = File('core/sing-box.exe');
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('singfox_test');
    await Paths.init(tmp);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  test('runtime config passes sing-box check', () async {
    final s = Settings()..tun = true;
    final extras = ProfileExtras()
      ..disabledRules = {1}
      ..ruleSets = [
        {'tag': 'geosite-openai', 'url': '${RuleMarket.rawBase}/geo/geosite/openai.srs', 'detour': '节点选择'}
      ]
      ..rules = [
        {'rule_set': ['geosite-openai'], 'outbound': '节点选择'}
      ];
    final cfg = ConfigBuilder.build(_profile, s, extras);
    final rules = cfg['route']['rules'] as List;
    expect(rules.where((r) => r['domain_suffix'] != null), isEmpty, reason: 'disabled rule removed');
    expect(rules.any((r) => r['clash_mode'] == 'Global'), isTrue);
    expect((cfg['inbounds'] as List).map((i) => i['type']), ['mixed', 'tun']);
    expect((cfg['outbounds'] as List).any((o) => o['type'] == 'direct'), isTrue);

    final f = File('${tmp.path}/cfg.json')..writeAsStringSync(jsonEncode(cfg));
    final r = await Process.run(core.absolute.path, ['check', '-c', f.path, '--disable-color']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }, skip: !core.existsSync());

  test('redir-host DNS plan passes sing-box check', () async {
    final profile = jsonDecode(_profile) as Map<String, dynamic>;
    profile['dns'] = {
      'servers': [
        {'type': 'udp', 'tag': 'old', 'server': '8.8.8.8'},
        {'type': 'fakeip', 'tag': 'fake'},
      ],
      'final': 'old',
    };
    (profile['outbounds'] as List)[0]
      ..['server'] = 'node.example.com'
      ..['domain_resolver'] = 'fake';
    final s = Settings()
      ..dnsLocal = ['tls://dns.alidns.com']
      ..dnsRemote = ['https://dns.google/dns-query'];
    final cfg = ConfigBuilder.build(jsonEncode(profile), s, ProfileExtras());
    final dns = cfg['dns'] as Map;
    final tags = (dns['servers'] as List).map((e) => e['tag']).toList();
    expect(tags, ['old', 'sf-local-1', 'sf-remote-1', 'sf-bootstrap']);
    expect((dns['rules'] as List).last, {'action': 'respond'});
    expect((cfg['outbounds'] as List)[0]['domain_resolver'], 'sf-local-1');
    expect(cfg['route']['default_domain_resolver'], 'sf-local-1');

    final f = File('${tmp.path}/dns.json')..writeAsStringSync(jsonEncode(cfg));
    final r = await Process.run(core.absolute.path, ['check', '-c', f.path, '--disable-color']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }, skip: !core.existsSync());

  test('DNS plan with server groups passes sing-box check', () async {
    final s = Settings()
      ..dnsLocal = ['https://223.5.5.5/dns-query', '119.29.29.29']
      ..dnsRemote = ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query', 'tls://9.9.9.9'];
    final cfg = ConfigBuilder.build(_profile, s, ProfileExtras());
    final rules = (cfg['dns'] as Map)['rules'] as List;
    expect(rules.where((r) => r['race'] == true).length, 2 * 2 + 3 * 2 + 3 + 3);
    final out = Platform.environment['SINGFOX_DUMP'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(cfg));

    final f = File('${tmp.path}/dns2.json')..writeAsStringSync(jsonEncode(cfg));
    final r = await Process.run(core.absolute.path, ['check', '-c', f.path, '--disable-color']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }, skip: !core.existsSync());

  test('DNS server specs', () {
    expect(DnsPlan.server('https://1.1.1.1/dns-query', 't'), {'type': 'https', 'tag': 't', 'server': '1.1.1.1'});
    expect(DnsPlan.server('223.5.5.5', 't'), {'type': 'udp', 'tag': 't', 'server': '223.5.5.5'});
    expect(DnsPlan.server('h3://dns.google:8443/q', 't'), {'type': 'h3', 'tag': 't', 'server': 'dns.google', 'server_port': 8443, 'path': '/q'});
    expect(DnsPlan.server('local', 't'), {'type': 'local', 'tag': 't'});
  });

  test('system proxy reads without writing', () {
    final (on, server) = SystemProxy.read();
    expect(on, isA<bool>());
    expect(server, isA<String>());
    expect(SystemProxy.serverFor(7890), '127.0.0.1:7890');
  }, skip: !Platform.isWindows);

  test('update check reports an unpublished repository (network)', () async {
    final info = await Updater.checkCore('2b90409');
    expect(info.published, isFalse);
    expect(info.url, contains('github.com/${Updater.coreRepo}'));
  }, tags: 'network');

  group('schema completion', () {
    late ConfigSchema schema;
    setUpAll(() async {
      File('assets/schema/sing-box.schema.json').copySync(Paths.I.schemaFile.path);
      schema = await ConfigSchema.load();
    });

    (String, List<String>)? at(String text) {
      final i = text.indexOf('|');
      final r = schema.complete(text.replaceFirst('|', ''), i);
      return r == null ? null : (r.$1, r.$2.map((e) => e.word).toList());
    }

    test('top-level keys', () {
      final r = at('{\n  "out|');
      expect(r!.$2, contains('outbounds'));
    });

    test('tls keys inside a vless outbound', () {
      final r = at('{"outbounds":[{"type":"vless","tls":{"enabled":true,"re|"}}]}');
      expect(r!.$1, 're');
      expect(r.$2, contains('reality'));
      expect(r.$2, isNot(contains('enabled')));
    });

    test('outbound fields follow the type', () {
      final r = at('{"outbounds":[{"type":"vless","fl|"}]}');
      expect(r!.$2, contains('flow'));
      final h = at('{"outbounds":[{"type":"hysteria2","up|"}]}');
      expect(h!.$2, contains('up_mbps'));
    });

    test('type values and transport enum', () {
      expect(at('{"outbounds":[{"type":"vl|"}]}')!.$2, contains('vless'));
      expect(at('{"outbounds":[{"type":"vless","transport":{"type":"x|"}}]}')!.$2, contains('xhttp'));
    });

    test('tag references', () {
      final r = at('{"outbounds":[{"type":"direct","tag":"direct-out"}],"route":{"final":"di|"}}');
      expect(r!.$2, contains('direct-out'));
    });
  });

  test('market lists geosite from GitHub (network)', () async {
    final items = await RuleMarket.refresh();
    final tags = items.map((i) => i.tag).toSet();
    expect(tags, containsAll(['geosite-openai', 'geosite-youtube', 'geoip-cn']));
    expect(tags.any((t) => t.startsWith('asn-')), isTrue);
  }, tags: 'network', timeout: const Timeout(Duration(minutes: 2)));

  test('market tree parsing', () {
    final items = RuleMarket.parse(['geo/geosite/openai.srs', 'geo/geoip/cn.srs', 'geo-lite/geosite/cn.srs', 'asn/AS13335.srs', 'README.md']);
    expect(items.map((i) => i.tag), containsAll(['geosite-openai', 'geoip-cn', 'lite-geosite-cn', 'asn-AS13335']));
  });
}
