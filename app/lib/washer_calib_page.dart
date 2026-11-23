import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'theme.dart';
import 'ui_helpers.dart';

/// Kalibrasi mesin cuci (butuh terhubung): belajar motor, uji putar, hitungan Hall per putaran, dosis pompa sabun.
class WasherCalibPage extends StatefulWidget {
  const WasherCalibPage(this.m, {super.key});
  final MachineLink m;
  @override
  State<WasherCalibPage> createState() => _WasherCalibPageState();
}

class _WasherCalibPageState extends State<WasherCalibPage> {
  MachineLink get m => widget.m;
  final soapSecCtl = TextEditingController(text: '10');
  final soapMlCtl = TextEditingController();
  final targetMlCtl = TextEditingController();
  final turnsCtl = TextEditingController(text: '1');
  int testDir = 0, testSec = 8;
  double testRpm = 60;
  int? edges0;
  int? edgesDelta;
  int soapProg = 0;

  @override
  void dispose() {
    soapSecCtl.dispose();
    soapMlCtl.dispose();
    targetMlCtl.dispose();
    turnsCtl.dispose();
    super.dispose();
  }

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NeuBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: pal(context).accent, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Future<void> _do(Future<Reply> f, String okMsg) async {
    final r = await f;
    if (mounted) snack(context, r.ok ? okMsg : errText(r.info));
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kalibrasi motor dan sabun'), actions: const [ThemeToggle()]),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final w = m.wstatus;
          final mo = m.motor;
          if (!m.isReady || w == null) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Mesin tidak terhubung.\nHubungkan mesin untuk kalibrasi.', textAlign: TextAlign.center)));
          }
          final en = w.canEdit && (w.state == 0 || w.state == 1);
          final mlps = (_num(soapMlCtl) != null && _num(soapSecCtl) != null && _num(soapSecCtl)! > 0) ? _num(soapMlCtl)! / _num(soapSecCtl)! : null;
          final perRev = (edgesDelta != null && (_num(turnsCtl) ?? 0) > 0) ? edgesDelta! / _num(turnsCtl)! : null;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (!en) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Kalibrasi hanya saat mesin OFF / layar pilihan.', style: TextStyle(color: p.sub))),
            _card('Status motor (langsung)', [
              Text('Putaran: ${mo?.rpm.toStringAsFixed(1) ?? '-'} rpm   •   tenaga: ${mo?.duty ?? '-'} ‰', style: TextStyle(color: p.text)),
              Text('Kode Hall: ${mo?.hall ?? '-'}   •   hitungan: ${mo?.edges ?? '-'}   •   riak: ${mo?.ripple.toStringAsFixed(1) ?? '-'} %', style: TextStyle(color: p.text)),
              Text('Driver IPM: ${(mo?.vfoOk ?? true) ? 'OK' : 'FAULT'}   •   motor ${w.learned ? 'sudah dipelajari (s=${m.devParams['mot_s']}, k=${m.devParams['mot_k']})' : 'BELUM dipelajari'}', style: TextStyle(color: w.learned ? p.text : Theme.of(context).colorScheme.error)),
            ]),
            _card('1. Pelajari motor otomatis', [
              Text('Mencoba 12 kombinasi urutan fasa/Hall pada tenaga rendah, memilih yang berputar paling baik. Syarat: drum KOSONG, pengujian dengan trafo isolasi + lampu seri, polaritas IPM sudah dicek, USB tidak terpasang. Hasil tersimpan otomatis di mesin.', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: en
                    ? () async {
                        final ok = await confirm(context, 'Pelajari motor?', 'Motor akan bergerak sebentar-sebentar selama ±15 detik. Pastikan drum kosong dan tidak ada yang menyentuh drum.', ok: 'MULAI');
                        if (ok && mounted) _do(m.learnMotor(), 'Perintah dikirim. Tunggu hasil di notifikasi (±15 detik).');
                      }
                    : null,
                icon: const Icon(Icons.psychology),
                label: const Text('Pelajari motor'),
              ),
            ]),
            _card('2. Uji putar motor', [
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 0, label: Text('Arah 0')), ButtonSegment(value: 1, label: Text('Arah 1'))],
                selected: {testDir},
                onSelectionChanged: (s) => setState(() => testDir = s.first),
              ),
              Slider(value: testRpm, min: 20, max: 250, divisions: 23, label: '${testRpm.round()} rpm', onChanged: (v) => setState(() => testRpm = v)),
              Text('${testRpm.round()} rpm  •  $testSec detik', style: TextStyle(color: p.text)),
              Slider(value: testSec.toDouble(), min: 3, max: 30, divisions: 27, onChanged: (v) => setState(() => testSec = v.round())),
              FilledButton.icon(
                onPressed: en && w.learned ? () => _do(m.testMotor(testDir, testRpm.round(), testSec), 'Uji putar dimulai') : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Uji putar'),
              ),
            ]),
            _card('3. Hitungan Hall per putaran drum', [
              Text('Dengan mesin OFF, tekan Mulai, putar drum dengan tangan tepat beberapa putaran penuh, lalu tekan Selesai. Makin banyak putaran makin akurat.', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: turnsCtl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Jumlah putaran drum', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: mo == null ? null : () => setState(() { edges0 = mo.edges; edgesDelta = null; }), child: const Text('Mulai')),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: (mo == null || edges0 == null) ? null : () => setState(() => edgesDelta = mo.edges - edges0!), child: const Text('Selesai')),
              ]),
              if (perRev != null) ...[
                const SizedBox(height: 8),
                Text('Hasil: ${perRev.toStringAsFixed(1)} hitungan per putaran', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                FilledButton(
                  onPressed: en && perRev >= 6 && perRev <= 2000 ? () => _do(m.setDeviceParam('hall_per_rev', perRev.round().toString()), 'hall_per_rev diterapkan. Tekan SIMPAN di bawah.') : null,
                  child: const Text('Terapkan'),
                ),
              ],
            ]),
            _card('4. Dosis pompa sabun', [
              Text('Nyalakan pompa beberapa detik, tampung cairan, ukur mililiternya, lalu aplikasi menghitung detik yang dibutuhkan per cucian.', style: TextStyle(color: p.sub, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: soapSecCtl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Lama uji (detik, 1-30)', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: en ? () => _do(m.testSoap((_num(soapSecCtl) ?? 10).round().clamp(1, 30)), 'Pompa sabun menyala') : null, child: const Text('Nyalakan')),
              ]),
              const SizedBox(height: 10),
              TextField(controller: soapMlCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Hasil takar (ml)', border: OutlineInputBorder())),
              if (mlps != null) ...[
                const SizedBox(height: 8),
                Text('Debit pompa: ${mlps.toStringAsFixed(2)} ml/detik', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(controller: targetMlCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Sabun yang diinginkan per cucian (ml)', border: OutlineInputBorder())),
                if (_num(targetMlCtl) != null) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final sec = (_num(targetMlCtl)! / mlps).round();
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('= $sec detik', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                      Row(children: [
                        Expanded(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: soapProg,
                            items: [for (int i = 0; i < m.schema.n; i++) DropdownMenuItem(value: i, child: Text(m.profile.programs[i].name))],
                            onChanged: (v) => setState(() => soapProg = v ?? 0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: sec >= 0 && sec <= 60
                              ? () {
                                  final pr = m.profile.programs[soapProg];
                                  final nv = List<int>.of(pr.v)..[9] = sec;
                                  final err = m.editProgram(soapProg, pr.withValues(nv));
                                  snack(context, err ?? 'Lama sabun ${pr.name} = $sec detik (draft, kirim dengan SYNC)');
                                }
                              : null,
                          child: const Text('Terapkan'),
                        ),
                      ]),
                      if (sec > 60) Text('Lebih dari 60 detik: tidak diizinkan firmware.', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ]);
                  }),
                ],
              ],
            ]),
            FilledButton.icon(
              onPressed: en ? () => _do(m.saveDevice(), 'Kalibrasi tersimpan permanen di mesin') : null,
              icon: const Icon(Icons.save),
              label: const Text('SIMPAN KALIBRASI'),
            ),
          ]);
        },
      ),
    );
  }
}
