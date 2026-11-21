import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'ui_helpers.dart';

/// Kalibrasi butuh mesin terhubung (membaca sensor langsung). Hasilnya langsung ke ESP32, bukan draft.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage(this.m, {super.key});
  final MachineLink m;
  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  MachineLink get m => widget.m;
  final refCtl = TextEditingController();
  final t1Ctl = TextEditingController();
  final t2Ctl = TextEditingController();
  double? ohm1, ohm2;

  @override
  void dispose() {
    refCtl.dispose();
    t1Ctl.dispose();
    t2Ctl.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _calOffset() async {
    final ref = _num(refCtl);
    if (ref == null) return snack(context, 'Isi suhu referensi');
    final r = await m.calRef(ref);
    if (mounted) snack(context, r.ok ? 'Offset dikalibrasi. Tekan SIMPAN KALIBRASI.' : errText(r.info));
  }

  void _capture(int n) {
    final t = _num(n == 1 ? t1Ctl : t2Ctl);
    final o = m.avgOhm;
    if (t == null) return snack(context, 'Isi suhu referensi titik $n');
    if (o == null) return snack(context, 'Pembacaan NTC belum cukup, tunggu beberapa detik');
    setState(() => n == 1 ? ohm1 = o : ohm2 = o);
  }

  Future<void> _applyBeta() async {
    final t1 = _num(t1Ctl), t2 = _num(t2Ctl);
    if (t1 == null || t2 == null || ohm1 == null || ohm2 == null) return snack(context, 'Ambil kedua titik dulu');
    if ((t1 - t2).abs() < 15) return snack(context, 'Beda suhu dua titik minimal 15 °C');
    final beta = math.log(ohm1! / ohm2!) / (1 / (t1 + 273.15) - 1 / (t2 + 273.15));
    if (beta.isNaN || beta < 2500 || beta > 4500) {
      return snack(context, 'Hasil beta ${beta.toStringAsFixed(0)} tidak masuk akal, ulangi pengukuran');
    }
    final ok = await confirm(context, 'Terapkan beta?',
        'Beta hasil hitung: ${beta.toStringAsFixed(0)}\n(sebelumnya ${m.devParams['ntc_beta'] ?? '-'})\n\nSetelah itu lakukan kalibrasi offset 1 titik.', ok: 'TERAPKAN');
    if (!ok) return;
    final r = await m.setDeviceParam('ntc_beta', beta.toStringAsFixed(0));
    if (mounted) snack(context, r.ok ? 'Beta diterapkan. Tunggu 5 detik lalu kalibrasi offset.' : errText(r.info));
  }

  Widget _pointRow(String label, TextEditingController c, double? ohm, VoidCallback onTap, bool en) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '$label - suhu referensi (°C)', border: const OutlineInputBorder(),
                helperText: ohm == null ? 'belum diambil' : 'diambil: ${ohm.toStringAsFixed(0)} Ω'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: en ? onTap : null, child: const Text('Ambil')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalibrasi sensor suhu')),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final s = m.status;
          if (!m.isReady || s == null) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Mesin tidak terhubung.\nHubungkan mesin untuk kalibrasi.', textAlign: TextAlign.center)));
          }
          final th = Theme.of(context);
          final en = s.canEdit;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Pembacaan langsung', style: th.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(s.sensorOk ? '${s.temp.toStringAsFixed(1)} °C  (terkalibrasi)' : 'Sensor tidak terbaca', style: th.textTheme.headlineSmall),
                  Text('Mentah: ${s.raw.toStringAsFixed(1)} °C   •   NTC: ${s.ohm} Ω'),
                  Text('Offset: ${m.devParams['ntc_off'] ?? '-'} °C   •   Beta: ${m.devParams['ntc_beta'] ?? '-'}'),
                ]),
              ),
            ),
            if (!en) const ListTile(leading: Icon(Icons.lock), title: Text('Kalibrasi terkunci saat mesin berjalan')),
            const SizedBox(height: 8),
            Text('1. Kalibrasi offset (1 titik)', style: th.textTheme.titleMedium),
            const Text('Letakkan termometer referensi di tempat yang sama dengan NTC, tunggu stabil ±30 detik, isi nilainya.'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: refCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Suhu referensi (°C)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: en ? _calOffset : null, child: const Text('Kalibrasi')),
            ]),
            const SizedBox(height: 24),
            Text('2. Kalibrasi beta (2 titik, opsional)', style: th.textTheme.titleMedium),
            const Text('Ambil dua titik suhu yang berjauhan (mis. suhu ruang dan ±60 °C), lalu terapkan beta. Setelah itu ulangi langkah 1.'),
            const SizedBox(height: 8),
            _pointRow('Titik 1', t1Ctl, ohm1, () => _capture(1), en),
            _pointRow('Titik 2', t2Ctl, ohm2, () => _capture(2), en),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: en ? _applyBeta : null, child: const Text('Hitung dan terapkan beta')),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: en
                  ? () async {
                      final r = await m.saveDevice();
                      if (context.mounted) snack(context, r.ok ? 'Kalibrasi tersimpan permanen di mesin' : errText(r.info));
                    }
                  : null,
              icon: const Icon(Icons.save),
              label: const Text('SIMPAN KALIBRASI'),
            ),
          ]);
        },
      ),
    );
  }
}
