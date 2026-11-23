import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'app_settings_page.dart';
import 'history.dart';
import 'machine_link.dart';
import 'machine_page.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_helpers.dart';

class MachineListPage extends StatelessWidget {
  const MachineListPage({super.key});

  static const _types = [
    ('dryer', 'Dryer', Icons.air),
    ('washer', 'Mesin Cuci', Icons.local_laundry_service),
  ];

  String _sub(MachineLink m) {
    if (m.phase == LinkPhase.connecting || m.phase == LinkPhase.authing) return 'Menghubungkan...';
    if (m.phase == LinkPhase.ready) {
      if (!m.hasStatus) return 'Terhubung';
      final base = 'Terhubung  •  ${m.isDryer ? m.status!.stateText : m.wstatus!.stateText}';
      if (!m.running) return base;
      return '$base  •  ${fmtTime(m.remainS)}';
    }
    if (m.profile.deviceId == null) return 'Belum dipasangkan ke ESP32 (mode offline)';
    return m.lastError != null ? 'Offline  •  ${m.lastError}' : 'Offline';
  }

  Widget _tile(BuildContext context, MachineLink m, IconData icon) {
    final p = pal(context);
    final on = m.isReady;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: NeuBox(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MachinePage(m))),
        child: Row(children: [
          NeuBox(circle: true, depth: 0.5, padding: const EdgeInsets.all(12), child: Icon(icon, color: on ? Colors.green : p.sub)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.profile.name, style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text(_sub(m), style: TextStyle(color: p.sub, fontSize: 12)),
            ]),
          ),
          if (m.needsSync) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.sync_problem, color: Colors.orange)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                final t = await askText(context, 'Nama mesin', m.profile.name, number: false);
                if (t == null) return;
                final err = m.rename(t);
                if (err != null && context.mounted) snack(context, err);
              } else if (v == 'delete') {
                final ok = await confirm(context, 'Hapus "${m.profile.name}"?', 'Mesin dihapus dari aplikasi (setting di ESP32 tidak ikut terhapus).', ok: 'HAPUS');
                if (ok) await store.remove(m);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
              PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesin saya'),
        actions: [
          IconButton(tooltip: 'Riwayat order', icon: const Icon(Icons.receipt_long), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()))),
          const ThemeToggle(),
          IconButton(tooltip: 'Tampilan', icon: const Icon(Icons.palette_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsPage()))),
          IconButton(tooltip: 'Hubungkan ulang semua', icon: const Icon(Icons.bluetooth_searching), onPressed: store.connectAll),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMachinePage())),
        icon: const Icon(Icons.add),
        label: const Text('Tambah mesin'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.machines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Belum ada mesin.\nTekan "Tambah mesin" untuk menambah dryer atau mesin cuci.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            for (final t in _types)
              if (store.byType(t.$1).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Row(children: [
                    Icon(t.$3, size: 20, color: p.accent),
                    const SizedBox(width: 8),
                    Text('${t.$2} (${store.byType(t.$1).length})', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  ]),
                ),
                for (final m in store.byType(t.$1)) _tile(context, m, t.$3),
              ],
          ]);
        },
      ),
    );
  }
}
