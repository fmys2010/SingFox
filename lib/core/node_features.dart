/// Short labels for the notable parts of an outbound's config, shown on node
/// cards, most telling first: security layer, transport, flow, then the rest.
List<String> nodeFeatures(Map<String, dynamic> o) {
  final f = <String>[];
  final tls = o['tls'] as Map?;
  final secure = tls?['enabled'] == true;
  if (secure) f.add((tls?['reality'] as Map?)?['enabled'] == true ? 'Reality' : 'TLS');
  final transport = o['transport'] as Map?;
  if (transport != null) {
    final type = transport['type'] as String? ?? '';
    final label = switch (type) {
      'ws' => 'WS',
      'grpc' => 'gRPC',
      'http' => 'H2',
      'httpupgrade' => 'HTTPUpgrade',
      'quic' => 'QUIC',
      'xhttp' => 'XHTTP',
      _ => type,
    };
    final mode = transport['mode'] as String?;
    f.add(type == 'xhttp' && mode != null && mode.isNotEmpty && mode != 'auto' ? '$label·$mode' : label);
  }
  final flow = o['flow'] as String?;
  if (flow != null && flow.isNotEmpty) f.add(flow.endsWith('vision') ? 'Vision' : flow);
  final enc = o['encryption'] as String?;
  if (enc != null && enc.isNotEmpty && enc != 'none') f.add('Encryption');
  if (secure && (tls?['ech'] as Map?)?['enabled'] == true) f.add('ECH');
  if (secure && (tls?['utls'] as Map?)?['enabled'] == true) f.add('uTLS');
  final mux = o['multiplex'] as Map?;
  if (mux?['enabled'] == true) f.add('Mux·${mux?['protocol'] ?? 'h2mux'}');
  if (o['type'] == 'shadowsocks') {
    final method = o['method'] as String? ?? '';
    f.add(method.startsWith('2022-') ? 'SS2022' : method);
    if (o['plugin'] != null) f.add('${o['plugin']}');
  }
  if ((o['obfs'] as Map?)?['type'] != null) f.add('Obfs');
  if (o['server_ports'] != null) f.add('端口跳跃');
  final cc = o['congestion_control'] as String?;
  if (cc != null && cc.isNotEmpty) f.add(cc.toUpperCase());
  if (o['udp_over_tcp'] == true || (o['udp_over_tcp'] as Map?)?['enabled'] == true) f.add('UoT');
  if (o['tcp_fast_open'] == true) f.add('TFO');
  if (o['detour'] != null) f.add('链式');
  return f;
}
