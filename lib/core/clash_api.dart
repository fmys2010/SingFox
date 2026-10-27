import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client for the core's Clash-compatible controller API.
class ClashApi {
  ClashApi(this.port, this.secret);

  final int port;
  final String secret;
  final _client = http.Client();

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('http://127.0.0.1:$port$path').replace(queryParameters: q);
  Map<String, String> get _h => {'Authorization': 'Bearer $secret', 'Content-Type': 'application/json'};

  Future<dynamic> _json(Future<http.Response> f) async {
    final r = await f.timeout(const Duration(seconds: 10));
    if (r.statusCode >= 400) throw Exception('API ${r.statusCode}: ${r.body}');
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// HTTP status of /version, 0 when nothing answered.
  Future<int> probe() async {
    try {
      final r = await _client.get(_u('/version'), headers: _h).timeout(const Duration(milliseconds: 800));
      return r.statusCode;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> ping() async => await probe() == 200;

  Future<Map<String, dynamic>> proxies() async => (await _json(_client.get(_u('/proxies'), headers: _h)))['proxies'] as Map<String, dynamic>;

  Future<void> select(String group, String name) =>
      _json(_client.put(_u('/proxies/${Uri.encodeComponent(group)}'), headers: _h, body: jsonEncode({'name': name})));

  /// [unified] times a second request on the opened connection, leaving out
  /// the TCP, TLS and proxy handshakes (SingFox's core only).
  Future<int?> delay(String name, String url, {int timeout = 5000, bool unified = false}) async {
    try {
      final j = await _json(_client.get(
          _u('/proxies/${Uri.encodeComponent(name)}/delay', {'url': url, 'timeout': '$timeout', if (unified) 'unified': 'true'}),
          headers: _h));
      return j['delay'] as int?;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setMode(String mode) => _json(_client.patch(_u('/configs'), headers: _h, body: jsonEncode({'mode': mode})));

  Future<void> closeConnection(String id) => _json(_client.delete(_u('/connections/$id'), headers: _h));
  Future<void> closeAll() => _json(_client.delete(_u('/connections'), headers: _h));

  Stream<dynamic> stream(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('ws://127.0.0.1:$port$path').replace(queryParameters: {...?q, 'token': secret});
    final ch = WebSocketChannel.connect(uri);
    return ch.stream.map((e) => jsonDecode(e as String));
  }

  void close() => _client.close();
}
