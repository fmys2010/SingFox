import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'platform.dart';
/// Checks GitHub releases for SingFox and its core, pre-releases included.
class Updater {
  static const appVersion = '1.0.5';
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

  /// Downloads the core of [info] into [dir] as `sing-box-<tag>(.exe)` and
  /// returns it. A new file name each time keeps a running core binary from
  /// being locked, and the app's own install folder may not be writable.
  static Future<File> downloadCore(UpdateInfo info, Directory dir, {int? proxyPort, void Function(double)? onProgress}) async {
    final url = info.asset;
    if (url == null) throw HttpException('该发布没有适用当前系统的内核压缩包');
    await dir.create(recursive: true);
    final sep = Platform.pathSeparator;
    final isTarGz = url.endsWith('.tar.gz');
    final archive = File('${dir.path}$sep${info.tag}${isTarGz ? '.tar.gz' : '.zip'}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'SingFox/$appVersion';
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('下载失败（HTTP ${res.statusCode}）');
      final sink = archive.openWrite();
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
      final expectedSha = info.sha256ForAsset(info.assetName ?? '');
      if (expectedSha.isNotEmpty) {
        final got = (await crypto.sha256.bind(archive.openRead()).first).toString();
        if (got != expectedSha) throw const HttpException('SHA-256 校验失败，文件已丢弃');
      }
      final tmp = Directory('${dir.path}${sep}extract');
      if (await tmp.exists()) await tmp.delete(recursive: true);
      await tmp.create();
      final tarBin = Platform.isWindows ? '${Platform.environment['SystemRoot'] ?? 'C:/Windows'}/System32/tar.exe' : 'tar';
      final x = await Process.run(tarBin, ['-xf', archive.path, '-C', tmp.path]);
      if (x.exitCode != 0) throw HttpException('解压失败：${x.stderr}');
      final targetName = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
      final exe = await tmp
          .list(recursive: true)
          .where((e) => e is File && e.path.toLowerCase().endsWith('$sep$targetName'))
          .cast<File>()
          .cast<File?>()
          .firstWhere((_) => true, orElse: () => null);
      if (exe == null) throw HttpException('压缩包里没有 $targetName');
      if (!Platform.isWindows) await Process.run('chmod', ['+x', exe.path]);
      final v = await Process.run(exe.path, ['version']);
      if (v.exitCode != 0) throw const HttpException('下载的内核无法运行');
      final ext = Platform.isWindows ? '.exe' : '';
      final dest = File('${dir.path}${sep}sing-box-${info.tag}$ext');
      if (await dest.exists()) await dest.delete();
      await exe.rename(dest.path);
      if (!Platform.isWindows) await Process.run('chmod', ['+x', dest.path]);
      await tmp.delete(recursive: true);
      return dest;
    } finally {
      if (await archive.exists()) await archive.delete();
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
        asset = _coreAsset(r)?.$2,
        assetName = _coreAsset(r)?.$1,
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
        assetName = null,
        assets = const [],
        sha256 = '',
        url = 'https://github.com/$repo/releases',
        date = null;

  /// The SHA-256 the notes give for the APK: a line that mentions the APK or
  /// its file name. Empty when the notes have none.
  String sha256ForApk(String name) => sha256ForAsset(name, fallbackTag: 'APK');

  /// The SHA-256 the notes give for [name], falling back to the single `SHA-256:`
  /// field when the release only lists one digest.
  String sha256ForAsset(String name, {String? fallbackTag}) {
    if (name.isNotEmpty) {
      for (final line in notes.split('\n')) {
        if (!line.contains(name) && (fallbackTag == null || !line.contains(fallbackTag))) continue;
        final m = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(line);
        if (m != null) return m.group(0)!.toLowerCase();
      }
    }
    return sha256;
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

  /// Picks the matching core archive for the current desktop OS and arch.
  static (String, String)? _coreAsset(Map<String, dynamic> r) {
    final List<RegExp> patterns;
    if (Platform.isWindows) {
      patterns = [RegExp(r'^sing-box-.*windows-amd64\.zip$')];
    } else if (Platform.isMacOS) {
      final arch = PlatformHelper.macArch();
      patterns = [
        RegExp('^sing-box-.*darwin-$arch\\.tar\\.gz\$'),
        if (arch == 'arm64') RegExp(r'^sing-box-.*darwin-amd64\.tar\.gz$'),
      ];
    } else {
      return null;
    }
    for (final re in patterns) {
      for (final a in (r['assets'] as List? ?? [])) {
        final name = (a as Map)['name'] as String? ?? '';
        final url = a['browser_download_url'] as String? ?? '';
        if (re.hasMatch(name) && url.isNotEmpty) return (name, url);
      }
    }
    return null;
  }

  final bool published, newer;
  final String tag, name, notes, url, commit, sha256;
  final String? asset, assetName;
  final List<({String name, String url})> assets;
  final DateTime? date;
  bool get installable => asset != null;
}
