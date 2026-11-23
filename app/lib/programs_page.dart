import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

/// Program generik (dryer / mesin cuci): bidang-bidangnya dari MachineSchema.fields. Bisa diedit dan dikembalikan ke default.
class ProgramsPage extends StatelessWidget {
  const ProgramsPage(this.m, {super.key});
  final MachineLink m;

  bool _hidden(int field, List<int> v) => m.isDryer && field >= 2 && v[1] == 0;

  Future<void> _edit(BuildContext context, int i) async {
    final p0 = m.profile.programs[i];
    final fields = m.schema.fields;
    final vals = List<int>.of(p0.v);
    final ctl = [for (final v in vals) TextEditingController(text: '$v')];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(p0.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (int k = 0; k < fields.length; k++)
                if (!_hidden(k, vals))
                  fields[k].isBool
                      ? SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(fields[k].label), value: vals[k] == 1, onChanged: (v) => setS(() => vals[k] = v ? 1 : 0))
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextField(
                            controller: ctl[k],
                            keyboardType: TextInputType.number,
                            onChanged: (t) => vals[k] = int.tryParse(t.trim()) ?? vals[k],
                            decoration: InputDecoration(labelText: '${fields[k].label} (${fields[k].min}-${fields[k].max} ${fields[k].unit})', border: const OutlineInputBorder()),
                          ),
                        ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
            TextButton(
              onPressed: () {
                final def = m.schema.defProgs[i];
                setS(() {
                  for (int k = 0; k < def.length; k++) {
                    vals[k] = def[k];
                    ctl[k].text = '${def[k]}';
                  }
                });
              },
              child: const Text('Default'),
            ),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Terapkan')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final err = m.editProgram(i, p0.withValues(vals));
      if (context.mounted) snack(context, err ?? '${p0.name} diubah (kirim ke mesin dengan SYNC)');
    }
    for (final t in ctl) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Program'), actions: const [ThemeToggle()]),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          SyncBanner(m),
          for (int i = 0; i < m.schema.n; i++)
            Builder(builder: (context) {
              final prog = m.profile.programs[i];
              final changed = !prog.same(ProgramCfg(prog.name, m.schema.defProgs[i]));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NeuBox(
                  onTap: () => _edit(context, i),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. ${prog.name}${changed ? '   (diubah)' : ''}', style: TextStyle(color: changed ? p.accent : p.text, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(m.schema.summary(prog), style: TextStyle(color: p.sub, fontSize: 12)),
                      ]),
                    ),
                    if (changed)
                      IconButton(
                        tooltip: 'Kembalikan ke default',
                        icon: Icon(Icons.restart_alt, color: p.accent),
                        onPressed: () {
                          final err = m.resetProgram(i);
                          if (err != null) snack(context, err);
                        },
                      ),
                    Icon(Icons.edit, color: p.sub),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}
