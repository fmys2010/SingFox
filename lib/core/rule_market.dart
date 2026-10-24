import 'dart:convert';
import 'dart:io';

import 'paths.dart';

class MarketItem {
  MarketItem(this.category, this.name, this.path);

  /// geosite, geoip, asn, lite-geosite, lite-geoip.
  final String category;
  final String name;
  final String path;

  String get tag => '$category-$name';
  String get url => '${RuleMarket.rawBase}/$path';
}

/// Rule sets from MetaCubeX/meta-rules-dat (sing branch).
class RuleMarket {
  static const repo = 'MetaCubeX/meta-rules-dat';
  static const branch = 'sing';
  static const rawBase = 'https://raw.githubusercontent.com/$repo/$branch';
  static const _treeApi = 'https://api.github.com/repos/$repo/git/trees';

  static final _re = RegExp(r'^(geo|geo-lite)/(geosite|geoip)/([^/]+)\.srs$');
  static final _asn = RegExp(r'^asn/([^/]+)\.srs$');

  static List<MarketItem> parse(List paths) {
    final out = <MarketItem>[];
    for (final p in paths.cast<String>()) {
      final m = _re.firstMatch(p);
      if (m != null) {
        final cat = m.group(1) == 'geo-lite' ? 'lite-${m.group(2)}' : m.group(2)!;
        out.add(MarketItem(cat, m.group(3)!, p));
        continue;
      }
      final a = _asn.firstMatch(p);
      if (a != null) out.add(MarketItem('asn', a.group(1)!, p));
    }
    out.sort((a, b) => a.tag.compareTo(b.tag));
    return out;
  }

  static Future<(List<MarketItem>, DateTime?)> cached() async {
    final f = Paths.I.marketCache;
    if (!await f.exists()) return (<MarketItem>[], null);
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return (parse(j['paths'] as List), DateTime.tryParse(j['at'] ?? ''));
  }

  /// Fetches the branch's file list. [proxyPort] routes through the core.
  ///
  /// The tree is walked one level at a time: a recursive listing is cut off
  /// by the tens of thousands of ASN files before `geo/` is reached.
  static Future<List<MarketItem>> refresh({int? proxyPort}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';

    Future<List<Map<String, dynamic>>> tree(String sha) async {
      final req = await client.getUrl(Uri.parse('$_treeApi/$sha'));
      req.headers.set('User-Agent', 'SingFox');
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('GitHub 返回 HTTP ${res.statusCode}');
      return [for (final e in jsonDecode(body)['tree'] as List) (e as Map).cast<String, dynamic>()];
    }

    String? shaOf(List<Map<String, dynamic>> t, String name) => t.where((e) => e['path'] == name).map((e) => e['sha'] as String).firstOrNull;

    try {
      final paths = <String>[];
      final root = await tree(branch);
      for (final top in ['geo', 'geo-lite']) {
        final topSha = shaOf(root, top);
        if (topSha == null) continue;
        final sub = await tree(topSha);
        for (final kind in ['geosite', 'geoip']) {
          final sha = shaOf(sub, kind);
          if (sha == null) continue;
          for (final f in await tree(sha)) {
            if ((f['path'] as String).endsWith('.srs')) paths.add('$top/$kind/${f['path']}');
          }
        }
      }
      final asn = shaOf(root, 'asn');
      if (asn != null) {
        for (final f in await tree(asn)) {
          if ((f['path'] as String).endsWith('.srs')) paths.add('asn/${f['path']}');
        }
      }
      await Paths.I.marketCache.writeAsString(jsonEncode({'at': DateTime.now().toIso8601String(), 'paths': paths}));
      return parse(paths);
    } finally {
      client.close(force: true);
    }
  }
}
