import 'dart:convert';
import 'dart:io';

class ExitIp {
  ExitIp({
    required this.ip,
    required this.countryCode,
    required this.country,
    required this.location,
    required this.isp,
    required this.asn,
    required this.lat,
    required this.lon,
    required this.risk,
    required this.ipType,
    required this.flags,
  });

  final String ip, countryCode, country, location, isp, asn, ipType;
  final double lat, lon;

  /// IPPure fraud score, 0–100, higher is riskier; null when missing.
  final int? risk;
  final List<String> flags;
  final DateTime checkedAt = DateTime.now();

  String get riskLabel => risk == null ? '未知' : (risk! < 25 ? '低风险' : risk! < 60 ? '中风险' : '高风险');
}

/// Looks up the current exit IP with IPPure, through the core's mixed inbound.
class ExitIpService {
  static const url = 'https://my.ippure.com/v1/info';

  static Future<ExitIp> check(int proxyPort) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SingFox');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('IPPure 返回 HTTP ${res.statusCode}');
      return _parse(jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  static ExitIp _parse(Map<String, dynamic> j) {
    final place = [j['region'], j['city']].whereType<String>().where((e) => e.isNotEmpty).toSet().join(' · ');
    final score = j['fraudScore'] as num?;
    return ExitIp(
      ip: j['ip'] ?? '',
      countryCode: (j['countryCode'] ?? '').toString().toUpperCase(),
      country: j['country'] ?? '未知',
      location: place.isEmpty ? (j['country'] ?? '未知') : place,
      isp: j['asOrganization'] ?? '未知',
      asn: j['asn'] != null ? 'AS${j['asn']}' : '',
      lat: double.tryParse('${j['latitude']}') ?? 0,
      lon: double.tryParse('${j['longitude']}') ?? 0,
      risk: score?.round().clamp(0, 100),
      ipType: j['isResidential'] == true ? '住宅 IP' : '机房 IP',
      flags: [j['isBroadcast'] == true ? '广播 IP' : '原生 IP'],
    );
  }
}
