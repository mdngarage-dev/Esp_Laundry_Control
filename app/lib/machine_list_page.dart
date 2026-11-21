import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'machine_link.dart';
import 'machine_page.dart';
import 'store.dart';
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
      final s = m.status;
      if (s == null) return 'Terhubung';
      final base = 'Terhubung  •  ${s.stateText}';
      if (!s.running) return base;
      return '$base  •  ${fmtTime(s.remainS)}  •  ${s.sensorOk ? '${s.temp.round()}°C' : '--'}';
    }
    if (m.profile.deviceId == null) return 'Belum dipasangkan ke ESP32 (mode offline)';
    return m.lastError != null ? 'Offline  •  ${m.lastError}' : 'Offline';
  }

  Widget _tile(BuildContext context, MachineLink m, IconData icon) {
    final on = m.isReady;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: on ? Colors.green.shade700 : Colors.grey.shade700, child: Icon(icon, color: Colors.white)),
        title: Text(m.profile.name),
        subtitle: Text(_sub(m)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.needsSync) const Tooltip(message: 'Setting belum disinkron', child: Icon(Icons.sync_problem, color: Colors.orange)),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MachinePage(m))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesin saya'),
        actions: [
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
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final t in _types)
              if (store.byType(t.$1).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(children: [
                    Icon(t.$3, size: 20),
                    const SizedBox(width: 8),
                    Text('${t.$2} (${store.byType(t.$1).length})', style: Theme.of(context).textTheme.titleMedium),
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
