import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'ui_helpers.dart';

class OrderEntry {
  OrderEntry(this.order, this.machine, this.program, this.at);
  final String order, machine, program;
  final DateTime at;
  Map<String, dynamic> toJson() => {'o': order, 'm': machine, 'p': program, 't': at.toIso8601String()};
  factory OrderEntry.fromJson(Map<String, dynamic> j) =>
      OrderEntry(j['o'] as String, j['m'] as String, j['p'] as String, DateTime.parse(j['t'] as String));
}

/// Riwayat order yang selesai dikerjakan mesin (disimpan di HP).
class OrderLog extends ChangeNotifier {
  final List<OrderEntry> entries = [];

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString('order_log');
    if (raw == null) return;
    try {
      for (final e in jsonDecode(raw) as List) {
        entries.add(OrderEntry.fromJson(Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
  }

  Future<void> add(OrderEntry e) async {
    entries.insert(0, e);
    if (entries.length > 300) entries.removeRange(300, entries.length);
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('order_log', jsonEncode(entries.map((x) => x.toJson()).toList()));
  }

  Future<void> clear() async {
    entries.clear();
    notifyListeners();
    (await SharedPreferences.getInstance()).remove('order_log');
  }
}

final OrderLog orderLog = OrderLog();

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  String _fmt(DateTime d) {
    String t(int v) => v.toString().padLeft(2, '0');
    return '${t(d.day)}/${t(d.month)}/${d.year}  ${t(d.hour)}:${t(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat order'), actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await confirm(context, 'Hapus riwayat?', 'Semua riwayat order di aplikasi dihapus.', ok: 'HAPUS');
            if (ok) orderLog.clear();
          },
        ),
      ]),
      body: ListenableBuilder(
        listenable: orderLog,
        builder: (context, _) {
          if (orderLog.entries.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Belum ada order selesai.\nRiwayat tercatat saat mesin selesai mengerjakan order yang di-scan.', textAlign: TextAlign.center)));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final e in orderLog.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NeuBox(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long),
                    title: Text(e.order.isEmpty ? '(tanpa order)' : e.order),
                    subtitle: Text('${e.machine}  •  ${e.program}\n${_fmt(e.at)}'),
                    isThreeLine: true,
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
