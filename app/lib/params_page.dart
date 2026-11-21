import 'package:flutter/material.dart';

import 'defaults.dart';
import 'machine_link.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

class ParamsPage extends StatelessWidget {
  const ParamsPage(this.m, {super.key});
  final MachineLink m;

  Future<void> _set(BuildContext c, String key, String v) async {
    final err = m.editParam(key, v);
    if (err != null && c.mounted) snack(c, err);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan umum dan gas')),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final widgets = <Widget>[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SyncBanner(m)),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Perubahan disimpan di app dulu. Kirim ke mesin dengan tombol SYNC.', style: TextStyle(fontSize: 12)),
            ),
          ];
          String? group;
          for (final meta in kParamMeta) {
            if (meta.group != group) {
              group = meta.group;
              widgets.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(meta.group, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ));
            }
            final cur = m.profile.params[meta.key] ?? kDefaultParams[meta.key] ?? '0';
            if (meta.isBool) {
              widgets.add(SwitchListTile(
                title: Text(meta.title),
                subtitle: meta.note == null ? null : Text(meta.note!),
                value: cur != '0' && cur != '0.00',
                onChanged: (v) async {
                  if (meta.key == 'remote_start' && v) {
                    final ok = await confirm(context, 'Aktifkan mulai dari HP?',
                        'Ini bisa menyalakan gas dari jauh. Aktifkan hanya jika ada orang di dekat mesin dan ruangan berventilasi.', ok: 'AKTIFKAN');
                    if (!ok) return;
                  }
                  if (context.mounted) _set(context, meta.key, v ? '1' : '0');
                },
              ));
            } else {
              final shown = double.tryParse(cur) == null ? cur : fmtNum(double.parse(cur));
              widgets.add(ListTile(
                title: Text(meta.title),
                subtitle: Text('${meta.key}  •  batas ${fmtNum(meta.min)}-${fmtNum(meta.max)} ${meta.unit}'),
                trailing: Text('$shown ${meta.unit}', style: Theme.of(context).textTheme.titleMedium),
                onTap: () async {
                  final t = await askText(context, meta.title, shown, decimal: !meta.isInt);
                  if (t != null && context.mounted) _set(context, meta.key, t);
                },
              ));
            }
          }
          return ListView(children: widgets);
        },
      ),
    );
  }
}
