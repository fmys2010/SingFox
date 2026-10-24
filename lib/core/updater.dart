import 'dart:convert';
import 'dart:io';

/// Checks GitHub releases for SingFox and its core, pre-releases included.
class Updater {
  static const appVersion = '0.1.2-beta';
  static const appRepo = 'fmys2010/SingFox';
  static const coreRepo = 'fmys2010/singbox-x';

  /// Requests go through the local proxy while connected, since the GitHub
  /// API is often unreachable directly.
  static Future<Object?> _get(String path, int? proxyPort) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'SingFox/$appVersion';
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com$path')).timeout(const Duration(seconds: 10));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw HttpException('GitHub 返回 ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  /// The newer app release, null when up to date. Throws when unreachable;
  /// [UpdateInfo.unpublished] when the repository has no release yet.
  static Future<UpdateInfo> checkApp({int? proxyPort}) async {
    final r = await _latest(appRepo, proxyPort);
    if (r == null) return UpdateInfo.unpublished(appRepo);
    final tag = r['tag_name'] as String? ?? '';
    return UpdateInfo.fromRelease(r, newer: _compare(tag, appVersion) > 0);
  }

  /// A source-built core reports `original-singbox-x` instead of a version,
  /// so the release is compared by the commit it was built from.
  static Future<UpdateInfo> checkCore(String revision, {int? proxyPort}) async {
    final r = await _latest(coreRepo, proxyPort);
    if (r == null) return UpdateInfo.unpublished(coreRepo);
    final tag = r['tag_name'] as String? ?? '';
    final commit = await _get('/repos/$coreRepo/commits/${Uri.encodeComponent(tag)}', proxyPort) as Map?;
    final sha = commit?['sha'] as String? ?? '';
    final newer = revision.isEmpty || sha.isEmpty || !sha.startsWith(revision) && !revision.startsWith(sha);
    return UpdateInfo.fromRelease(r, newer: newer, commit: sha);
  }

  /// The newest published release, beta or not. `releases/latest` would
  /// skip pre-releases such as 0.1.2-beta.
  static Future<Map<String, dynamic>?> _latest(String repo, int? proxyPort) async {
    final list = await _get('/repos/$repo/releases?per_page=10', proxyPort) as List?;
    return list?.cast<Map<String, dynamic>>().where((r) => r['draft'] != true).firstOrNull;
  }

  /// Compares dotted versions, ignoring a leading `v` and any suffix.
  static int _compare(String a, String b) {
    List<int> parts(String v) => [for (final p in v.replaceFirst(RegExp('^v'), '').split(RegExp(r'[.+-]')).take(3)) int.tryParse(p) ?? 0];
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}

class UpdateInfo {
  UpdateInfo.fromRelease(Map<String, dynamic> r, {required this.newer, this.commit = ''})
      : published = true,
        tag = r['tag_name'] as String? ?? '',
        name = r['name'] as String? ?? '',
        notes = r['body'] as String? ?? '',
        url = r['html_url'] as String? ?? '',
        date = DateTime.tryParse(r['published_at'] as String? ?? '');

  UpdateInfo.unpublished(String repo)
      : published = false,
        newer = false,
        tag = '',
        name = '',
        notes = '',
        commit = '',
        url = 'https://github.com/$repo/releases',
        date = null;

  final bool published, newer;
  final String tag, name, notes, url, commit;
  final DateTime? date;
}
