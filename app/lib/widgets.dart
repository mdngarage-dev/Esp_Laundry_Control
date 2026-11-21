import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'ui_helpers.dart';

Future<void> doSync(BuildContext c, MachineLink m) async {
  final err = await m.sync();
  if (c.mounted) snack(c, err ?? 'Tersinkron dan tersimpan permanen di mesin');
}

/// Banner status sinkronisasi + keputusan saat draft app berbeda dengan isi mesin.
class SyncBanner extends StatelessWidget {
  const SyncBanner(this.m, {super.key});
  final MachineLink m;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final th = Theme.of(context);
        if (m.pendingDecision) {
          return Card(
            color: th.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Setting di app berbeda dengan yang ada di mesin. Pilih mana yang dipakai:'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: () async {
                      final err = await m.resolveSend();
                      if (context.mounted) snack(context, err ?? 'Setting app dikirim dan tersimpan permanen di mesin');
                    },
                    child: const Text('Kirim ke mesin'),
                  ),
                  OutlinedButton(onPressed: m.resolvePull, child: const Text('Ambil dari mesin')),
                ]),
              ]),
            ),
          );
        }
        if (!m.needsSync) return const SizedBox.shrink();
        final online = m.isReady;
        return Card(
          color: th.colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.sync_problem),
            title: Text(online ? 'Setting belum disinkron ke mesin' : 'Setting tersimpan di app, belum dikirim ke mesin'),
            subtitle: online ? null : Text(m.profile.deviceId == null ? 'Pasangkan ESP32 untuk sinkron' : 'Hubungkan mesin untuk sinkron'),
            trailing: online
                ? FilledButton(onPressed: m.syncing ? null : () => doSync(context, m), child: Text(m.syncing ? '...' : 'SYNC'))
                : null,
          ),
        );
      },
    );
  }
}
