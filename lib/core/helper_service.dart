import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'platform.dart';

/// Client for `singfox-service` (see service/), which runs the core as
/// SYSTEM so TUN works without starting SingFox elevated.
class HelperService {
  HelperService._();
  static final I = HelperService._();

  static const _base = 'http://127.0.0.1:47391';
  static String get _tokenFile => '${Platform.environment['ProgramData'] ?? r'C:\ProgramData'}\\SingFox\\service.token';

  String? _token;
  final _client = http.Client();

  Map<String, String> get _h => {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'};

  /// Whether the service is installed and answering for this user.
  Future<bool> available() async => (await status()) != null;

  Future<Map<String, dynamic>?> status() async {
    try {
      _token ??= (await File(_tokenFile).readAsString()).trim();
      final r = await _client.get(Uri.parse('$_base/status'), headers: _h).timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      _token = null;
      return null;
    }
  }

  /// Starts the core with [config]; throws with the core's message on failure.
  Future<void> start(String config) async {
    final r = await _client.post(Uri.parse('$_base/start'), headers: _h, body: config).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception((jsonDecode(r.body) as Map)['error'] ?? 'HTTP ${r.statusCode}');
  }

  Future<void> stop() async {
    await _client.post(Uri.parse('$_base/stop'), headers: _h).timeout(const Duration(seconds: 10));
  }

  /// Log lines after sequence number [after], as `(seq, text)`.
  Future<List<(int, String)>> logs(int after) async {
    final r = await _client.get(Uri.parse('$_base/logs?after=$after'), headers: _h).timeout(const Duration(seconds: 5));
    return [for (final e in jsonDecode(r.body) as List) (e['seq'] as int, e['text'] as String)];
  }

  /// Start the core with the last config when the service starts at boot.
  Future<void> setAutostart(bool on) async {
    await _client.post(Uri.parse('$_base/autostart'), headers: _h, body: jsonEncode({'autostart': on})).timeout(const Duration(seconds: 5));
  }

  /// The service binary shipped next to [core].
  static String serviceExe(String core) => '${File(core).parent.path}\\singfox-service.exe';

  /// Installs (or reinstalls, updating the core copy) with one UAC prompt.
  Future<String?> install(String core) async {
    final exe = serviceExe(core);
    if (!File(exe).existsSync()) return '找不到 singfox-service.exe';
    final sid = await PlatformHelper.userSid();
    if (sid == null) return '无法获取当前用户 SID';
    final code = await PlatformHelper.runElevated(exe, ['install', '--user-sid', sid, '--core', core]);
    _token = null;
    if (code != 0) return code == -1 ? '已取消授权' : '安装失败（代码 $code）';
    for (var i = 0; i < 20; i++) {
      if (await available()) return null;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return '服务已安装但没有响应';
  }

  Future<String?> uninstall(String core) async {
    final code = await PlatformHelper.runElevated(serviceExe(core), ['uninstall']);
    _token = null;
    return code == 0 ? null : (code == -1 ? '已取消授权' : '卸载失败（代码 $code）');
  }
}
