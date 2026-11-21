import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dryer_link.dart';
import 'ui_helpers.dart';

String _f(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

class _NumTile extends StatelessWidget {
  const _NumTile(this.title, this.k, this.unit, this.min, this.max, {this.isInt = true, required this.enabled});
  final String title, k, unit;
  final double min, max;
  final bool isInt, enabled;

  @override
  Widget build(BuildContext context) {
    final cur = link.params[k] ?? '-';
    return ListTile(
      enabled: enabled,
      title: Text(title),
      subtitle: Text('$k  •  batas ${_f(min)}-${_f(max)} $unit'),
      trailing: Text('$cur $unit', style: Theme.of(context).textTheme.titleMedium),
      onTap: () async {
        final t = await askText(context, title, cur == '-' ? '' : cur, decimal: !isInt);
        if (t == null) return;
        final v = double.tryParse(t.replaceAll(',', '.'));
        if (v == null || v < min || v > max) {
          if (context.mounted) snack(context, 'Nilai harus ${_f(min)}-${_f(max)}');
          return;
        }
        final r = await link.setParam(k, isInt ? v.round().toString() : v.toString());
        if (!r.ok && context.mounted) snack(context, errText(r.info));
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _setBool(BuildContext c, String key, bool v) async {
    final r = await link.setParam(key, v ? '1' : '0');
    if (!r.ok && c.mounted) snack(c, errText(r.info));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final en = link.status?.canEdit ?? false;
        if (!link.configLoaded) return const Center(child: CircularProgressIndicator());
        return ListView(children: [
          if (!en)
            const ListTile(
              leading: Icon(Icons.lock),
              title: Text('Setting terkunci saat mesin berjalan'),
              subtitle: Text('Hentikan mesin dulu untuk mengubah.'),
            ),
          const _Header('Pintu'),
          SwitchListTile(
            title: const Text('Lanjut otomatis setelah pintu ditutup'),
            subtitle: const Text('Mati = harus tekan LANJUT (di HP atau knob di mesin)'),
            value: link.doorResumeOn,
            onChanged: en ? (v) => _setBool(context, 'door_resume', v) : null,
          ),
          const _Header('Keamanan'),
          SwitchListTile(
            title: const Text('Izinkan mulai dari HP'),
            subtitle: const Text('Mati = pilih program dari HP, mulai dengan menekan knob di mesin'),
            value: link.remoteStartOn,
            onChanged: en
                ? (v) async {
                    if (v) {
                      final ok = await confirm(context, 'Aktifkan mulai dari HP?',
                          'Ini bisa menyalakan gas dari jauh. Aktifkan hanya jika ada orang di dekat mesin dan ruangan berventilasi.',
                          ok: 'AKTIFKAN');
                      if (!ok) return;
                    }
                    if (context.mounted) _setBool(context, 'remote_start', v);
                  }
                : null,
          ),
          ListTile(
            enabled: en,
            leading: const Icon(Icons.password),
            title: const Text('Ganti PIN'),
            subtitle: const Text('4-6 angka. Langsung disimpan ke mesin (ikut menyimpan perubahan lain).'),
            onTap: () async {
              final t = await askText(context, 'PIN baru', '');
              if (t == null) return;
              if (!RegExp(r'^\d{4,6}$').hasMatch(t)) {
                if (context.mounted) snack(context, 'PIN harus 4-6 angka');
                return;
              }
              final r = await link.setParam('pin', t);
              if (!r.ok) {
                if (context.mounted) snack(context, errText(r.info));
                return;
              }
              final sv = await link.save();
              if (sv.ok) {
                link.pin = t;
                final p = await SharedPreferences.getInstance();
                await p.setString('pin', t);
              }
              if (context.mounted) snack(context, sv.ok ? 'PIN diganti dan disimpan' : 'PIN diubah tapi GAGAL disimpan: ${errText(sv.info)}');
            },
          ),
          const _Header('Siklus gas dan pengaman'),
          _NumTile('Igniter memanas sebelum gas', 'ign_warm', 'detik', 20, 90, enabled: en),
          _NumTile('Tunda awal setelah motor ON', 'prestart', 'detik', 5, 60, enabled: en),
          _NumTile('Batas waktu pembuktian api', 'proof', 'detik', 15, 60, enabled: en),
          _NumTile('Kenaikan suhu bukti api', 'proof_rise', '°C', 0.5, 10, isInt: false, enabled: en),
          _NumTile('Jeda purge setelah gagal nyala', 'purge', 'detik', 30, 300, enabled: en),
          _NumTile('Jumlah coba ulang nyala', 'retry', 'x', 0, 3, enabled: en),
          _NumTile('Histeresis (gas nyala lagi di tCut - ini)', 'hyst', '°C', 2, 20, isInt: false, enabled: en),
          _NumTile('Batas error suhu terlalu panas', 't_hard', '°C', 50, 90, isInt: false, enabled: en),
          SwitchListTile(
            title: const Text('Matikan igniter setelah api terbukti'),
            subtitle: const Text('Aktifkan hanya jika igniter bukan tipe yang harus menyala terus'),
            value: params('ign_off_proof') == '1',
            onChanged: en ? (v) => _setBool(context, 'ign_off_proof', v) : null,
          ),
          const _Header('Tombol STOP'),
          _NumTile('Pendinginan maksimal', 'stopcool_s', 'detik', 30, 600, enabled: en),
          _NumTile('Selesai pendinginan di bawah', 'stopcool_t', '°C', 30, 60, enabled: en),
          const _Header('Sinkronisasi ke mesin'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: en
                    ? () async {
                        final r = await link.save();
                        if (context.mounted) snack(context, r.ok ? 'Tersimpan ke mesin' : errText(r.info));
                      }
                    : null,
                icon: const Icon(Icons.sync),
                label: const Text('SIMPAN (SYNC)'),
              ),
              OutlinedButton.icon(
                onPressed: en
                    ? () async {
                        final r = await link.reloadFromFlash();
                        if (context.mounted) snack(context, r.ok ? 'Dimuat ulang dari mesin' : errText(r.info));
                      }
                    : null,
                icon: const Icon(Icons.undo),
                label: const Text('Buang perubahan'),
              ),
              OutlinedButton.icon(
                onPressed: en
                    ? () async {
                        final ok = await confirm(context, 'Reset pabrik?', 'Semua setting, program, dan kalibrasi kembali ke nilai awal (PIN tetap).', ok: 'RESET');
                        if (!ok) return;
                        final r = await link.factoryDefaults();
                        if (context.mounted) snack(context, r.ok ? 'Nilai pabrik dipulihkan' : errText(r.info));
                      }
                    : null,
                icon: const Icon(Icons.restore),
                label: const Text('Reset pabrik'),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  String? params(String k) => link.params[k];
}

class _Header extends StatelessWidget {
  const _Header(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
