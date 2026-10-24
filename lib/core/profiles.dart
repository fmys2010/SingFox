import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'paths.dart';

enum ProfileKind { cloud, local, file }

/// SingFox-managed additions layered on top of a profile's own config.
class ProfileExtras {
  /// Indexes into the profile's own `route.rules` that are switched off.
  Set<int> disabledRules = {};

  /// Rule sets added from the market: {tag, url}.
  List<Map<String, dynamic>> ruleSets = [];

  /// Rules created alongside market rule sets: {rule_set: [...], outbound}.
  List<Map<String, dynamic>> rules = [];

  Map<String, dynamic> toJson() => {
        'disabledRules': disabledRules.toList(),
        'ruleSets': ruleSets,
        'rules': rules,
      };

  static ProfileExtras fromJson(Map<String, dynamic>? j) {
    final e = ProfileExtras();
    if (j == null) return e;
    e.disabledRules = {for (final i in (j['disabledRules'] as List? ?? [])) i as int};
    e.ruleSets = [for (final r in (j['ruleSets'] as List? ?? [])) Map<String, dynamic>.from(r)];
    e.rules = [for (final r in (j['rules'] as List? ?? [])) Map<String, dynamic>.from(r)];
    return e;
  }
}

class Profile {
  Profile({required this.id, required this.name, required this.kind});

  final String id;
  String name;
  ProfileKind kind;
  String url = '';
  String userAgent = 'sing-box original-singbox-x';
  int updateHours = 12;
  bool updateViaProxy = false;
  String filePath = '';
  bool watchFile = true;
  DateTime? updatedAt;
  int? upload, download, total;
  DateTime? expire;
  ProfileExtras extras = ProfileExtras();

  String get kindLabel => switch (kind) { ProfileKind.cloud => '云端', ProfileKind.local => '本地配置', ProfileKind.file => '本地文件' };

  String get initial => name.isEmpty ? '?' : name.characters1.toUpperCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'url': url,
        'userAgent': userAgent,
        'updateHours': updateHours,
        'updateViaProxy': updateViaProxy,
        'filePath': filePath,
        'watchFile': watchFile,
        'updatedAt': updatedAt?.toIso8601String(),
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.toIso8601String(),
        'extras': extras.toJson(),
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile(id: j['id'], name: j['name'], kind: ProfileKind.values.byName(j['kind']));
    p.url = j['url'] ?? '';
    p.userAgent = j['userAgent'] ?? p.userAgent;
    p.updateHours = j['updateHours'] ?? 12;
    p.updateViaProxy = j['updateViaProxy'] ?? false;
    p.filePath = j['filePath'] ?? '';
    p.watchFile = j['watchFile'] ?? true;
    p.updatedAt = DateTime.tryParse(j['updatedAt'] ?? '');
    p.upload = j['upload'];
    p.download = j['download'];
    p.total = j['total'];
    p.expire = DateTime.tryParse(j['expire'] ?? '');
    p.extras = ProfileExtras.fromJson(j['extras']);
    return p;
  }

  File get contentFile => File('${Paths.I.profiles.path}${Platform.pathSeparator}$id.json');
}

extension on String {
  String get characters1 => runes.isEmpty ? '' : String.fromCharCode(runes.first);
}

class ProfileStore {
  final List<Profile> items = [];

  static String newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<void> load() async {
    items.clear();
    final f = Paths.I.profilesFile;
    if (!await f.exists()) return;
    try {
      for (final j in jsonDecode(await f.readAsString()) as List) {
        items.add(Profile.fromJson(Map<String, dynamic>.from(j)));
      }
    } catch (_) {}
  }

  Future<void> save() => Paths.I.profilesFile
      .writeAsString(const JsonEncoder.withIndent('  ').convert([for (final p in items) p.toJson()]));

  Profile? byId(String? id) {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The profile's raw config text.
  Future<String> read(Profile p) async {
    if (p.kind == ProfileKind.file) return File(p.filePath).readAsString();
    if (!await p.contentFile.exists()) throw StateError('配置内容不存在，请先更新订阅');
    return p.contentFile.readAsString();
  }

  Future<void> writeLocal(Profile p, String text) async {
    validate(text);
    await p.contentFile.writeAsString(text);
    p.updatedAt = DateTime.now();
  }

  /// Throws a readable error when [text] is not a sing-box JSON config.
  static Map<String, dynamic> validate(String text) {
    final Object? v;
    try {
      v = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('不是有效的 JSON：${e.message}');
    }
    if (v is! Map<String, dynamic>) throw const FormatException('配置根节点必须是对象');
    if (v['outbounds'] is! List && v['endpoints'] is! List) {
      throw const FormatException('没有找到 outbounds，可能不是 sing-box 配置');
    }
    return v;
  }

  /// Downloads a cloud profile. [proxyPort] routes the request through the
  /// running core's mixed inbound.
  Future<void> update(Profile p, {int? proxyPort}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    if (proxyPort != null) client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    final http.Client c = IOClient(client);
    try {
      final res = await c.get(Uri.parse(p.url), headers: {'User-Agent': p.userAgent}).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('订阅返回 HTTP ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      try {
        validate(body);
      } on FormatException {
        throw const FormatException('订阅内容不是 sing-box JSON 配置（暂不支持 Clash / Base64 订阅）');
      }
      await p.contentFile.writeAsString(body);
      p.updatedAt = DateTime.now();
      _readUserInfo(p, res.headers['subscription-userinfo']);
    } finally {
      c.close();
    }
  }

  static void _readUserInfo(Profile p, String? header) {
    if (header == null) return;
    for (final part in header.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final n = int.tryParse(kv[1].trim());
      if (n == null) continue;
      switch (kv[0].trim()) {
        case 'upload':
          p.upload = n;
        case 'download':
          p.download = n;
        case 'total':
          p.total = n;
        case 'expire':
          p.expire = n > 0 ? DateTime.fromMillisecondsSinceEpoch(n * 1000) : null;
      }
    }
  }

  Future<void> remove(Profile p) async {
    items.remove(p);
    if (await p.contentFile.exists()) await p.contentFile.delete();
    await save();
  }
}
