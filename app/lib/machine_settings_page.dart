import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'calibration_page.dart';
import 'history.dart';
import 'knob_page.dart';
import 'machine_link.dart';
import 'params_page.dart';
import 'programs_page.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_helpers.dart';
import 'washer_calib_page.dart';
import 'widgets.dart';

class MachineSettingsPage extends StatelessWidget {
  const MachineSettingsPage(this.m, {super.key});
  final MachineLink m;

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  Widget _item(BuildContext context, IconData icon, String title, String sub, VoidCallback? onTap) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: NeuBox(
          onTap: onTap,
          child: Row(children: [
            Icon(icon, color: p.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(color: p.sub, fontSize: 12)),
              ]),
            ),
            Icon(Icons.chevron_right, color: p.sub),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final on = m.isReady;
        final orderOn = (m.profile.params['order_req'] ?? '0') == '1';
        return Scaffold(
          appBar: AppBar(title: Text('Pengaturan: ${m.profile.name}'), actions: const [ThemeToggle()]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            SyncBanner(m),
            _item(context, Icons.edit, 'Nama mesin', m.profile.name, () async {
              final t = await askText(context, 'Nama mesin', m.profile.name, number: false);
              if (t == null) return;
              final err = m.rename(t);
              if (err != null && context.mounted) snack(context, err);
            }),
            _item(context, Icons.tune, 'Pengaturan umum', m.isDryer ? 'Pintu, panas dan siklus gas, STOP, waktu' : 'Pintu & kunci, sabun, air, peras, motor, waktu', () => _go(context, ParamsPage(m))),
            _item(context, Icons.view_list, 'Program', m.isDryer ? 'Durasi, panas (suhu potong), siklus gas tiap program' : 'Waktu cuci/bilas/peras, putaran, sabun tiap program', () => _go(context, ProgramsPage(m))),
            _item(context, Icons.rotate_right, 'Langkah knob rotary', 'Atur program apa di tiap langkah putar', () => _go(context, KnobPage(m))),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NeuBox(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.qr_code_scanner, color: p.accent),
                  title: Text('Wajib scan barcode order', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  subtitle: Text('Mesin baru bisa mulai setelah barcode struk di-scan (juga untuk tombol di mesin). Kirim ke mesin dengan SYNC.', style: TextStyle(color: p.sub, fontSize: 12)),
                  value: orderOn,
                  onChanged: (v) {
                    final err = m.editParam('order_req', v ? '1' : '0');
                    if (err != null) snack(context, err);
                  },
                ),
              ),
            ),
            _item(context, Icons.receipt_long, 'Riwayat order', 'Order yang sudah selesai dikerjakan', () => _go(context, const HistoryPage())),
            _item(context, m.isDryer ? Icons.thermostat : Icons.science, m.isDryer ? 'Kalibrasi sensor suhu' : 'Kalibrasi motor dan sabun',
                on ? (m.isDryer ? 'Offset dan beta NTC' : 'Pelajari motor, uji putar, hitungan Hall, dosis sabun') : 'Hubungkan mesin dulu',
                on ? () => _go(context, m.isDryer ? CalibrationPage(m) : WasherCalibPage(m)) : null),
            _item(context, Icons.password, 'Ganti PIN', on ? '4-6 angka, langsung disimpan di mesin' : 'Hubungkan mesin dulu', on
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
                : null),
            _item(context, Icons.restore, 'Kembalikan ke nilai awal firmware', 'Setting, program, urutan knob (kalibrasi tetap). Berlaku di mesin setelah SYNC.', () async {
              final ok = await confirm(context, 'Kembalikan ke nilai awal?', 'Draft setting, program, dan urutan knob di app dikembalikan ke nilai awal firmware. Mesin belum berubah sampai SYNC.', ok: 'KEMBALIKAN');
              if (ok) m.resetDraft();
            }),
            _item(context, Icons.download, 'Ambil dari mesin (buang draft)', on && m.configLoaded ? 'Ganti draft di app dengan isi mesin' : 'Hubungkan mesin dulu', on && m.configLoaded
                ? () async {
                    final ok = await confirm(context, 'Buang draft?', 'Perubahan di app yang belum disinkron akan diganti dengan isi mesin.', ok: 'AMBIL');
                    if (ok) m.pullFromDevice();
                  }
                : null),
            _item(context, Icons.link, m.profile.deviceId == null ? 'Pasangkan ESP32' : 'Ganti ESP32 yang dipasangkan', m.profile.deviceId ?? 'Belum dipasangkan', () => _go(context, PairPage(m))),
            if (m.fwVersion.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('Firmware ${m.fwVersion}  •  ${m.devType}', style: TextStyle(color: p.sub, fontSize: 12))),
            _item(context, Icons.delete, 'Hapus mesin dari aplikasi', 'Setting di ESP32 tidak ikut terhapus', () async {
              final ok = await confirm(context, 'Hapus "${m.profile.name}"?', 'Setting di ESP32 tidak ikut terhapus.', ok: 'HAPUS');
              if (!ok) return;
              await store.remove(m);
              if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
            }),
          ]),
        );
      },
    );
  }
}
