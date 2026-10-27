import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Checks GitHub releases for SingFox and its core, pre-releases included.
class Updater {
  static const appVersion = '1.0.2';
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

  /// Downloads the core of [info] into [dir] as `sing-box-<tag>.exe` and
  /// returns it. A new file name each time keeps a running core's exe from
  /// being locked, and the app's own install folder may not be writable.
  static Future<File> downloadCore(UpdateInfo info, Directory dir, {int? proxyPort, void Function(double)? onProgress}) async {
    final url = info.asset;
    if (url == null) throw const HttpException('该发布没有 Windows 内核压缩包');
    await dir.create(recursive: true);
    final sep = Platform.pathSeparator;
    final zip = File('${dir.path}$sep${info.tag}.zip');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'SingFox/$appVersion';
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('下载失败（HTTP ${res.statusCode}）');
      final sink = zip.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (res.contentLength > 0) onProgress?.call(got / res.contentLength);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
    try {
      if (info.sha256.isNotEmpty) {
        final r = await Process.run('certutil', ['-hashfile', zip.path, 'SHA256']);
        final got = RegExp(r'^[0-9a-f]{64}$', multiLine: true).firstMatch((r.stdout as String).replaceAll(' ', '').toLowerCase())?.group(0);
        if (got != info.sha256) throw const HttpException('SHA-256 校验失败，文件已丢弃');
      }
      final tmp = Directory('${dir.path}${sep}extract');
      if (await tmp.exists()) await tmp.delete(recursive: true);
      await tmp.create();
      final x = await Process.run('${Platform.environment['SystemRoot'] ?? 'C:/Windows'}/System32/tar.exe', ['-xf', zip.path, '-C', tmp.path]);
      if (x.exitCode != 0) throw HttpException('解压失败：${x.stderr}');
      // Official archives nest the exe in a folder, ours is flat.
      final exe = await tmp.list(recursive: true).where((e) => e is File && e.path.toLowerCase().endsWith('${sep}sing-box.exe')).cast<File>().cast<File?>().firstWhere((_) => true, orElse: () => null);
      if (exe == null) throw const HttpException('压缩包里没有 sing-box.exe');
      final v = await Process.run(exe.path, ['version']);
      if (v.exitCode != 0) throw const HttpException('下载的内核无法运行');
      final dest = File('${dir.path}${sep}sing-box-${info.tag}.exe');
      if (await dest.exists()) await dest.delete();
      await exe.rename(dest.path);
      await tmp.delete(recursive: true);
      return dest;
    } finally {
      if (await zip.exists()) await zip.delete();
    }
  }

  /// The newest core release against the version bundled in this app, by dotted
  /// number. Android ships the core inside the APK.
  static Future<UpdateInfo> checkBundledCore(String version, {int? proxyPort}) async {
    final r = await _latest(coreRepo, proxyPort);
    if (r == null) return UpdateInfo.unpublished(coreRepo);
    final tag = r['tag_name'] as String? ?? '';
    return UpdateInfo.fromRelease(r, newer: version.isNotEmpty && _compare(tag, version, parts: 4) > 0);
  }

  /// Downloads [url] to [dest], checking [sha256] when given.
  static Future<File> download(String url, File dest, {String sha256 = '', int? proxyPort, void Function(double)? onProgress}) async {
    await dest.parent.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'SingFox/$appVersion';
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    final part = File('${dest.path}.part');
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('下载失败（HTTP ${res.statusCode}）');
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (res.contentLength > 0) onProgress?.call(got / res.contentLength);
        }
      } finally {
        await sink.close();
      }
      if (sha256.isNotEmpty && (await crypto.sha256.bind(part.openRead()).first).toString() != sha256) {
        throw const HttpException('SHA-256 校验失败，文件已丢弃');
      }
      if (await dest.exists()) await dest.delete();
      return await part.rename(dest.path);
    } finally {
      client.close(force: true);
      if (await part.exists()) await part.delete();
    }
  }

  /// The newest published release, beta or not. `releases/latest` would
  /// skip pre-releases such as 0.1.2-beta.
  static Future<Map<String, dynamic>?> _latest(String repo, int? proxyPort) async {
    final list = await _get('/repos/$repo/releases?per_page=10', proxyPort) as List?;
    return list?.cast<Map<String, dynamic>>().where((r) => r['draft'] != true).firstOrNull;
  }

  /// Compares dotted versions, ignoring a leading `v` and any suffix.
  static int _compare(String a, String b, {int parts = 3}) {
    List<int> split(String v) => [for (final p in v.replaceFirst(RegExp('^v'), '').split(RegExp(r'[.+-]')).take(parts)) int.tryParse(p) ?? 0];
    final x = split(a), y = split(b);
    for (var i = 0; i < parts; i++) {
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
        date = DateTime.tryParse(r['published_at'] as String? ?? ''),
        asset = _windowsAsset(r),
        assets = [
          for (final a in (r['assets'] as List? ?? []))
            (name: (a as Map)['name'] as String? ?? '', url: a['browser_download_url'] as String? ?? '')
        ],
        sha256 = RegExp(r'SHA-256:\s*([0-9a-fA-F]{64})').firstMatch(r['body'] as String? ?? '')?.group(1)?.toLowerCase() ?? '';

  UpdateInfo.unpublished(String repo)
      : published = false,
        newer = false,
        tag = '',
        name = '',
        notes = '',
        commit = '',
        asset = null,
        assets = const [],
        sha256 = '',
        url = 'https://github.com/$repo/releases',
        date = null;

  /// The SHA-256 the notes give for the APK: a line that mentions the APK or
  /// its file name. Empty when the notes have none.
  String sha256ForApk(String name) {
    for (final line in notes.split('\n')) {
      if (!line.contains('APK') && !line.contains(name)) continue;
      final m = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(line);
      if (m != null) return m.group(0)!.toLowerCase();
    }
    return '';
  }

  /// The Android APK for the first of [abis] the release has one for; a lone
  /// APK is the fallback.
  ({String name, String url})? apkFor(List<String> abis) {
    final apks = [for (final a in assets) if (a.name.endsWith('.apk')) a];
    for (final abi in abis) {
      for (final a in apks) {
        if (a.name.contains(abi)) return a;
      }
    }
    return apks.length == 1 ? apks.first : null;
  }

  /// The core zip for 64-bit Windows, null when the release has none.
  static String? _windowsAsset(Map<String, dynamic> r) {
    for (final a in (r['assets'] as List? ?? [])) {
      final name = (a as Map)['name'] as String? ?? '';
      if (RegExp(r'^sing-box-.*windows-amd64\.zip$').hasMatch(name)) return a['browser_download_url'] as String?;
    }
    return null;
  }

  final bool published, newer;
  final String tag, name, notes, url, commit, sha256;
  final String? asset;
  final List<({String name, String url})> assets;
  final DateTime? date;
  bool get installable => asset != null;
}
