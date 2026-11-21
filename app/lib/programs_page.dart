import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

class ProgramsPage extends StatelessWidget {
  const ProgramsPage(this.m, {super.key});
  final MachineLink m;

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  Future<void> _edit(BuildContext context, int i) async {
    final p = m.profile.programs[i];
    final cm = TextEditingController(text: '${p.minutes}');
    final con = TextEditingController(text: '${p.onS}');
    final coff = TextEditingController(text: '${p.offS}');
    final ctc = TextEditingController(text: '${p.tCut}');
    final ccool = TextEditingController(text: '${p.coolS}');
    bool heat = p.heat == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(p.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(cm, 'Durasi total (menit, 5-240)'),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pakai gas + igniter'), value: heat, onChanged: (v) => setS(() => heat = v)),
              if (heat) ...[
                _field(con, 'Gas nyala (detik, 30-900)'),
                _field(coff, 'Gas mati (detik, 10-900)'),
                _field(ctc, 'Suhu potong tCut (°C, 40 sampai batas error-5)'),
                _field(ccool, 'Pendinginan akhir maks (detik, 0-900)'),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Terapkan')),
          ],
        ),
      ),
    );
    int g(TextEditingController t, int def) => int.tryParse(t.text.trim()) ?? def;
    if (ok == true) {
      final np = p.copyWith(
          minutes: g(cm, p.minutes), heat: heat ? 1 : 0, onS: g(con, p.onS), offS: g(coff, p.offS), tCut: g(ctc, p.tCut), coolS: g(ccool, p.coolS));
      final err = m.editProgram(i, np);
      if (context.mounted) snack(context, err ?? '${p.name} diubah (kirim ke mesin dengan SYNC)');
    }
    for (final t in [cm, con, coff, ctc, ccool]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Program')),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(12), children: [
          SyncBanner(m),
          for (int i = 0; i < 9; i++)
            Card(
              child: ListTile(
                title: Text('${i + 1}. ${m.profile.programs[i].name}'),
                subtitle: Text(m.profile.programs[i].heat == 0
                    ? '${m.profile.programs[i].minutes} menit  •  angin saja (tanpa gas)'
                    : '${m.profile.programs[i].minutes} menit  •  gas ${m.profile.programs[i].onS}s nyala / ${m.profile.programs[i].offS}s mati  •  potong ${m.profile.programs[i].tCut}°C  •  dingin akhir ${m.profile.programs[i].coolS}s'),
                trailing: const Icon(Icons.edit),
                onTap: () => _edit(context, i),
              ),
            ),
        ]),
      ),
    );
  }
}
