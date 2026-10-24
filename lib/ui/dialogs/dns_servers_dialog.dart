import 'package:flutter/material.dart';

import '../../core/dns.dart';
import '../../theme.dart';
import '../widgets.dart';

/// Edits a DNS server group: one to [DnsPlan.maxServers] entries, queried in
/// parallel. Returns the new list, or null when cancelled.
Future<List<String>?> editDnsServers(BuildContext context, {required String title, required String hint, required List<String> servers}) =>
    showDialog<List<String>>(
      context: context,
      barrierColor: const Color(0x9E000000),
      builder: (_) => _DnsServersDialog(title: title, hint: hint, servers: servers),
    );

class _DnsServersDialog extends StatefulWidget {
  const _DnsServersDialog({required this.title, required this.hint, required this.servers});

  final String title, hint;
  final List<String> servers;

  @override
  State<_DnsServersDialog> createState() => _DnsServersDialogState();
}

class _DnsServersDialogState extends State<_DnsServersDialog> {
  late final _rows = [for (final s in widget.servers) TextEditingController(text: s)];

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _rows.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _rows) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final list = [for (final c in _rows) if (c.text.trim().isNotEmpty) c.text.trim()];
    if (list.isEmpty) return toast(context, '至少保留一个服务器', error: true);
    Navigator.pop(context, list);
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: SF.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF26262B))),
        child: SizedBox(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: SF.t(16, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(widget.hint, style: SF.t(12.5, color: SF.text3)),
              const SizedBox(height: 18),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: SF.m(12, color: SF.text3))),
                    Expanded(child: SFInput(controller: _rows[i], mono: true, background: SF.bg, hint: 'https://223.5.5.5/dns-query', onSubmitted: (_) => _save())),
                    const SizedBox(width: 8),
                    SFIconButton(
                      Icons.remove,
                      tooltip: '移除',
                      onTap: _rows.length > 1 ? () => setState(() => _rows.removeAt(i).dispose()) : null,
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              Row(children: [
                SFButton(
                  '添加服务器',
                  icon: Icons.add,
                  height: 30,
                  onTap: _rows.length < DnsPlan.maxServers ? () => setState(() => _rows.add(TextEditingController())) : null,
                ),
                const SizedBox(width: 12),
                Text('${_rows.length} / ${DnsPlan.maxServers}', style: SF.m(12, color: SF.text3)),
              ]),
              const SizedBox(height: 14),
              Text('支持 https:// · tls:// · quic:// · h3:// · tcp:// · udp:// 或纯 IP；local 表示系统 DNS', style: SF.t(12, color: SF.text3)),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                SFButton('取消', onTap: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                SFButton('保存', kind: BtnKind.primary, onTap: _save),
              ]),
            ]),
          ),
        ),
      );
}
