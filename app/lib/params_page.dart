import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'schema.dart';
import 'theme.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

/// Semua nilai di sini adalah DEFAULT dari firmware yang bisa diubah. Nilai yang berbeda dari default ditandai
/// dan bisa dikembalikan satu per satu. Perubahan disimpan sebagai draft, dikirim ke mesin dengan SYNC.
class ParamsPage extends StatelessWidget {
  const ParamsPage(this.m, {super.key});
  final MachineLink m;

  Future<void> _set(BuildContext c, String key, String v) async {
    final err = m.editParam(key, v);
    if (err != null && c.mounted) snack(c, err);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan umum'), actions: const [ThemeToggle()]),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final w = <Widget>[
            SyncBanner(m),
            Text('Nilai awal berasal dari firmware dan semuanya bisa diubah. Ikon ↺ mengembalikan ke nilai awal.', style: TextStyle(fontSize: 12, color: p.sub)),
          ];
          String? group;
          for (final meta in m.schema.params) {
            if (meta.group != group) {
              group = meta.group;
              w.add(Padding(padding: const EdgeInsets.fromLTRB(4, 20, 4, 8), child: Text(meta.group, style: TextStyle(color: p.accent, fontWeight: FontWeight.w700))));
            }
            final def = m.schema.defParams[meta.key] ?? '0';
            final cur = m.profile.params[meta.key] ?? def;
            final changed = !sameNum(cur, def);
            final defShown = double.tryParse(def) == null ? def : fmtNum(double.parse(def));
            final shown = double.tryParse(cur) == null ? cur : fmtNum(double.parse(cur));
            Widget tile;
            if (meta.isBool) {
              tile = SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(meta.title, style: TextStyle(color: p.text)),
                subtitle: Text('${meta.note ?? ''}${meta.note == null ? '' : '\n'}default: ${defShown == '1' ? 'aktif' : 'mati'}', style: TextStyle(color: p.sub, fontSize: 12)),
                value: cur != '0' && cur != '0.00',
                onChanged: (v) async {
                  if (meta.key == 'remote_start' && v) {
                    final ok = await confirm(context, 'Aktifkan mulai dari HP?', 'Ini bisa menjalankan mesin dari jauh. Aktifkan hanya jika ada orang di dekat mesin.', ok: 'AKTIFKAN');
                    if (!ok) return;
                  }
                  if (context.mounted) _set(context, meta.key, v ? '1' : '0');
                },
              );
            } else {
              tile = ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(meta.title, style: TextStyle(color: p.text)),
                subtitle: Text('${meta.key}  •  batas ${fmtNum(meta.min)}-${fmtNum(meta.max)} ${meta.unit}  •  default $defShown${meta.note == null ? '' : '\n${meta.note}'}', style: TextStyle(color: p.sub, fontSize: 12)),
                trailing: Text('$shown ${meta.unit}', style: TextStyle(color: changed ? p.accent : p.text, fontWeight: FontWeight.w700)),
                onTap: () async {
                  final t = await askText(context, meta.title, shown, decimal: !meta.isInt);
                  if (t != null && context.mounted) _set(context, meta.key, t);
                },
              );
            }
            w.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NeuBox(
                depth: 0.6,
                padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                child: Row(children: [
                  Expanded(child: tile),
                  if (changed)
                    IconButton(tooltip: 'Kembalikan ke default', icon: Icon(Icons.restart_alt, color: p.accent), onPressed: () => _set(context, meta.key, def)),
                ]),
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.all(16), children: w);
        },
      ),
    );
  }
}
