import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'calibration_page.dart';
import 'knob_page.dart';
import 'machine_link.dart';
import 'params_page.dart';
import 'programs_page.dart';
import 'store.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

class MachineSettingsPage extends StatelessWidget {
  const MachineSettingsPage(this.m, {super.key});
  final MachineLink m;

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final dryer = m.profile.type == 'dryer';
        final on = m.isReady;
        return Scaffold(
          appBar: AppBar(title: Text('Pengaturan: ${m.profile.name}')),
          body: ListView(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SyncBanner(m)),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Nama mesin'),
              subtitle: Text(m.profile.name),
              onTap: () async {
                final t = await askText(context, 'Nama mesin', m.profile.name, number: false);
                if (t == null) return;
                final err = m.rename(t);
                if (err != null && context.mounted) snack(context, err);
              },
            ),
            if (dryer) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Pengaturan umum dan gas'),
                subtitle: const Text('Pintu, keamanan, siklus gas, STOP'),
                onTap: () => _go(context, ParamsPage(m)),
              ),
              ListTile(
                leading: const Icon(Icons.view_list),
                title: const Text('Program'),
                subtitle: const Text('Durasi, siklus gas, suhu potong per program'),
                onTap: () => _go(context, ProgramsPage(m)),
              ),
              ListTile(
                leading: const Icon(Icons.rotate_right),
                title: const Text('Langkah knob rotary'),
                subtitle: const Text('Atur program apa di tiap langkah putar'),
                onTap: () => _go(context, KnobPage(m)),
              ),
              const Divider(),
              ListTile(
                enabled: on,
                leading: const Icon(Icons.thermostat),
                title: const Text('Kalibrasi sensor suhu'),
                subtitle: Text(on ? 'Offset dan beta NTC' : 'Hubungkan mesin dulu'),
                onTap: on ? () => _go(context, CalibrationPage(m)) : null,
              ),
              ListTile(
                enabled: on,
                leading: const Icon(Icons.password),
                title: const Text('Ganti PIN'),
                subtitle: Text(on ? '4-6 angka, langsung disimpan di mesin' : 'Hubungkan mesin dulu'),
                onTap: on
                    ? () async {
                        final t = await askText(context, 'PIN baru', '');
                        if (t == null) return;
                        if (!RegExp(r'^\d{4,6}$').hasMatch(t)) {
                          if (context.mounted) snack(context, 'PIN harus 4-6 angka');
                          return;
                        }
                        final err = await m.changePin(t);
                        if (context.mounted) snack(context, err ?? 'PIN diganti dan disimpan');
                      }
                    : null,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Kembalikan draft ke nilai awal'),
                subtitle: const Text('Setting, program, dan urutan knob (kalibrasi tetap). Berlaku di mesin setelah SYNC.'),
                onTap: () async {
                  final ok = await confirm(context, 'Kembalikan ke nilai awal?', 'Draft setting, program, dan urutan knob di app dikembalikan. Mesin belum berubah sampai SYNC.', ok: 'KEMBALIKAN');
                  if (ok) m.resetDraft();
                },
              ),
              ListTile(
                enabled: on && m.configLoaded,
                leading: const Icon(Icons.download),
                title: const Text('Ambil dari mesin (buang draft)'),
                onTap: on && m.configLoaded
                    ? () async {
                        final ok = await confirm(context, 'Buang draft?', 'Perubahan di app yang belum disinkron akan diganti dengan isi mesin.', ok: 'AMBIL');
                        if (ok) m.pullFromDevice();
                      }
                    : null,
              ),
            ],
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(m.profile.deviceId == null ? 'Pasangkan ESP32' : 'Ganti ESP32 yang dipasangkan'),
              subtitle: Text(m.profile.deviceId ?? 'Belum dipasangkan'),
              onTap: () => _go(context, PairPage(m)),
            ),
            if (m.fwVersion.isNotEmpty) ListTile(leading: const Icon(Icons.info_outline), title: Text('Firmware ${m.fwVersion}  •  ${m.devType}')),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: const Text('Hapus mesin dari aplikasi'),
              onTap: () async {
                final ok = await confirm(context, 'Hapus "${m.profile.name}"?', 'Setting di ESP32 tidak ikut terhapus.', ok: 'HAPUS');
                if (!ok) return;
                await store.remove(m);
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              },
            ),
          ]),
        );
      },
    );
  }
}
